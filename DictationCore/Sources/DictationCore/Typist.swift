import Foundation
import NaturalLanguage

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
    private static let properNounTags: Set<NLTag> = [.personalName, .placeName, .organizationName]
    private static let tagger = NLTagger(tagSchemes: [.nameType])
    private static let taggerLanguage: NLLanguage = Locale.current.language.languageCode
        .map { NLLanguage($0.identifier) }
        .flatMap { NLTagger.availableTagSchemes(for: .word, language: $0).contains(.nameType) ? $0 : nil }
        ?? .english

    private var typed = ""
    private var separator = ""
    private var continueSentence = false
    private var fieldID: UUID?

    public nonisolated init() {}

    /// Starts a new utterance at the cursor, separated from any preceding word by a space
    /// and continuing the sentence when the cursor is not after a sentence boundary.
    public mutating func begin(in target: TextTarget) {
        typed = ""
        fieldID = target.fieldID
        let before = target.textBeforeCursor
        separator = before?.last.map { $0.isWhitespace ? "" : " " } ?? ""
        continueSentence = Self.endsMidSentence(before)
    }

    /// Returns `false`, touching nothing, when `target` is not the field the utterance began
    /// in: the focus moved, and retyping there would eat text this dictation never typed.
    @discardableResult
    public mutating func update(to transcript: String, in target: TextTarget) -> Bool {
        guard target.fieldID == fieldID else { return false }
        let adjusted = continueSentence ? Self.lowercasingFirstIfNeeded(transcript) : transcript
        let wanted = adjusted.isEmpty ? "" : separator + adjusted
        let shared = zip(typed, wanted).prefix(while: ==).count
        for _ in shared..<typed.count { target.deleteBackward() }
        if shared < wanted.count { target.insert(String(wanted.dropFirst(shared))) }
        typed = wanted
        return true
    }

    private static func endsMidSentence(_ text: String?) -> Bool {
        guard let last = text?.reversed().first(where: { !$0.isWhitespace || $0.isNewline }) else {
            return false
        }
        return !last.isNewline && !".!?".contains(last)
    }

    private static func lowercasingFirstIfNeeded(_ transcript: String) -> String {
        guard let first = transcript.first, first.isUppercase else { return transcript }
        tagger.string = transcript
        tagger.setLanguage(taggerLanguage, range: transcript.startIndex..<transcript.endIndex)
        let (tag, range) = tagger.tag(at: transcript.startIndex, unit: .word, scheme: .nameType)
        let word = transcript[range]
        if word == "I" || tag.map(properNounTags.contains) == true { return transcript }
        let letters = word.filter(\.isLetter)
        if letters.count >= 2 && letters.allSatisfy(\.isUppercase) { return transcript }
        return first.lowercased() + transcript.dropFirst()
    }
}
