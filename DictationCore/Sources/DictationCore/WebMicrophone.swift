import WebKit

/// Captures the microphone through a `WKWebView`.
///
/// A keyboard extension cannot reliably run an audio engine of its own, but WebKit records
/// in its own helper processes. The page behind `webView` opens the microphone with
/// `getUserMedia` and streams PCM back here as `MicEvent`s.
///
/// `webView` has no visible content. The owner must keep it in an on-screen view hierarchy,
/// because WebKit pauses capture for pages that are not visible.
@MainActor
public final class WebMicrophone {
    public let webView: WKWebView
    public var onEvent: ((MicEvent) -> Void)?

    private let bridge = Bridge()

    public init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // The page starts its AudioContext from script, without a touch.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // Serving the page from a custom scheme makes it a secure context, which
        // `getUserMedia` and audio worklets require, without any network access.
        configuration.setURLSchemeHandler(bridge, forURLScheme: Bridge.scheme)
        configuration.userContentController.addScriptMessageHandler(bridge, contentWorld: .page, name: "mic")
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = bridge
        webView.navigationDelegate = bridge
        bridge.receive = { [weak self] in self?.onEvent?($0) }
        webView.load(URLRequest(url: Bridge.page))
    }

    public func open() {
        webView.evaluateJavaScript("void Mic.open()")
    }

    public func close() {
        webView.evaluateJavaScript("Mic.close()")
    }

    /// A file of the capture page, bundled with this package.
    nonisolated static func resource(_ name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Web")
    }
}

/// The WebKit-facing half of `WebMicrophone`. WebKit retains its handlers, so they live in a
/// separate object to avoid a reference cycle with the web view's owner.
private final class Bridge: NSObject, WKURLSchemeHandler, WKScriptMessageHandlerWithReply, WKUIDelegate, WKNavigationDelegate {
    static let scheme = "inplace-mic"
    static let page = URL(string: "\(scheme)://page/mic.html")!

    var receive: ((MicEvent) -> Void)?

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url,
              let file = WebMicrophone.resource(url.lastPathComponent),
              let body = try? Data(contentsOf: file)
        else { return task.didFailWithError(URLError(.fileDoesNotExist)) }
        let type = file.pathExtension == "html" ? "text/html" : "text/javascript"
        task.didReceive(URLResponse(url: url, mimeType: type, expectedContentLength: body.count, textEncodingName: "utf-8"))
        task.didReceive(body)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    /// The reply doubles as the acknowledgement the page uses to detect a stalled keyboard.
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
        if let event = MicEvent(message: message.body) { receive?(event) }
        return (nil, nil)
    }

    func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin, initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision {
        // The system-level microphone permission still applies; this only skips the
        // per-page prompt, and only for our own page.
        origin.protocol == Self.scheme && type == .microphone ? .grant : .deny
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        receive?(.ended(reason: "web-process-terminated"))
        webView.load(URLRequest(url: Self.page))
    }
}
