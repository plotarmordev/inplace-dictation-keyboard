import Testing
import WebKit
@testable import DictationCore

@Suite struct WebMicrophoneTests {
    /// The page must load from the bundle into a context where WebKit allows capture.
    @MainActor @Test(.timeLimit(.minutes(1)))
    func pageLoadsReadyToCapture() async throws {
        let microphone = WebMicrophone()
        let first = await withCheckedContinuation { continuation in
            microphone.onEvent = { event in
                microphone.onEvent = nil
                continuation.resume(returning: event)
            }
        }
        #expect(first == .ready)

        let capable = try await microphone.webView.evaluateJavaScript(
            "isSecureContext && typeof navigator.mediaDevices.getUserMedia === 'function' && typeof AudioWorkletNode === 'function' && typeof Mic.open === 'function'"
        ) as? Bool
        #expect(capable == true)
    }
}
