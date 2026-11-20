import Foundation

/// A text field the keyboard can type into; `UITextDocumentProxy` in the extension.
@MainActor
public protocol TextTarget {
    /// Differs between text fields, so a change of focus can be noticed.
    var fieldID: UUID { get }
    var textBeforeCursor: String? { get }
    func insert(_ text: String)
    func deleteBackward()
}

/// Keeps the text field in step with a transcript that is revised as recognition proceeds,
/// retyping only the part that changed.
@MainActor
public struct Typist {
    private var typed = ""
    private var separator = ""
    private var fieldID: UUID?

    public nonisolated init() {}

    /// Starts a new utterance at the cursor, separated from any preceding word by a space.
    public mutating func begin(in target: TextTarget) {
        typed = ""
        fieldID = target.fieldID
        let previous = target.textBeforeCursor?.last
        separator = previous.map { $0.isWhitespace ? "" : " " } ?? ""
    }

    /// Returns `false`, touching nothing, when `target` is not the field the utterance began
    /// in: the focus moved, and retyping there would eat text this dictation never typed.
    @discardableResult
    public mutating func update(to transcript: String, in target: TextTarget) -> Bool {
        guard target.fieldID == fieldID else { return false }
        let wanted = transcript.isEmpty ? "" : separator + transcript
        let shared = zip(typed, wanted).prefix(while: ==).count
        for _ in shared..<typed.count { target.deleteBackward() }
        if shared < wanted.count { target.insert(String(wanted.dropFirst(shared))) }
        typed = wanted
        return true
    }
}
