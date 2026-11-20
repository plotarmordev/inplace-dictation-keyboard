import DictationCore
import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private lazy var dictation = Dictation(
        target: { [unowned self] in DocumentTarget(proxy: textDocumentProxy) },
        hasFullAccess: { [unowned self] in hasFullAccess }
    )

    override func viewDidLoad() {
        super.viewDidLoad()

        // The capture page draws nothing; it only has to be on screen for WebKit to record.
        let webView = dictation.microphone.webView
        webView.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        webView.isOpaque = false
        webView.isUserInteractionEnabled = false
        webView.accessibilityElementsHidden = true
        view.addSubview(webView)

        let bar = UIHostingController(rootView: KeyboardBar(
            dictation: dictation,
            showsGlobe: needsInputModeSwitchKey,
            onGlobe: { [unowned self] in advanceToNextInputMode() },
            onDelete: { [unowned self] in textDocumentProxy.deleteBackward() },
            onReturn: { [unowned self] in textDocumentProxy.insertText("\n") }
        ))
        bar.view.backgroundColor = .clear
        bar.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(bar)
        view.addSubview(bar.view)
        bar.didMove(toParent: self)

        let height = view.heightAnchor.constraint(equalToConstant: KeyboardBar.height)
        height.priority = .defaultHigh
        NSLayoutConstraint.activate([
            height,
            bar.view.topAnchor.constraint(equalTo: view.topAnchor),
            bar.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bar.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        dictation.stop()
    }
}

private struct DocumentTarget: TextTarget {
    let proxy: UITextDocumentProxy

    var fieldID: UUID { proxy.documentIdentifier }
    var textBeforeCursor: String? { proxy.documentContextBeforeInput }
    func insert(_ text: String) { proxy.insertText(text) }
    func deleteBackward() { proxy.deleteBackward() }
}
