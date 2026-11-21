import Foundation
import Testing
@testable import DictationCore

/// A text field that also counts keystrokes, to check how much gets retyped.
private final class Field: TextTarget {
    let fieldID = UUID()
    var text: String
    var nilWhenEmpty: Bool
    var deletions = 0
    var insertions: [String] = []

    init(_ text: String = "", nilWhenEmpty: Bool = false) {
        self.text = text
        self.nilWhenEmpty = nilWhenEmpty
    }

    var textBeforeCursor: String? { text.isEmpty && nilWhenEmpty ? nil : text }
    func insert(_ inserted: String) { text += inserted; insertions.append(inserted) }
    func deleteBackward() { text.removeLast(); deletions += 1 }
}

@MainActor @Suite struct TypistTests {
    @Test func appendsAsTheTranscriptGrows() {
        let field = Field()
        var typist = Typist()
        typist.begin(in: field)
        typist.update(to: "Hello", in: field)
        typist.update(to: "Hello world", in: field)

        #expect(field.text == "Hello world")
        #expect(field.insertions == ["Hello", " world"])
        #expect(field.deletions == 0)
    }

    @Test func leavesAnotherFieldAlone() {
        let first = Field()
        let second = Field("Keep me")
        var typist = Typist()
        typist.begin(in: first)
        typist.update(to: "Hello", in: first)

        let revised = typist.update(to: "Jello", in: second)
        let cleared = typist.update(to: "", in: second)

        #expect(!revised && !cleared)
        #expect(second.text == "Keep me")
        #expect(second.deletions == 0)
        #expect(first.text == "Hello")
    }

    @Test func retypesOnlyTheRevisedTail() {
        let field = Field()
        var typist = Typist()
        typist.begin(in: field)
        typist.update(to: "I scream", in: field)
        typist.update(to: "Ice cream", in: field)

        #expect(field.text == "Ice cream")
        #expect(field.deletions == "scream".count + 1)
        #expect(field.insertions.last == "ce cream")
    }

    @Test func leavesAnUnchangedTranscriptAlone() {
        let field = Field()
        var typist = Typist()
        typist.begin(in: field)
        typist.update(to: "Same", in: field)
        typist.update(to: "Same", in: field)

        #expect(field.insertions == ["Same"])
        #expect(field.deletions == 0)
    }

    @Test func removesTextTheRecogniserTakesBack() {
        let field = Field("Note: ")
        var typist = Typist()
        typist.begin(in: field)
        typist.update(to: "um", in: field)
        typist.update(to: "", in: field)

        #expect(field.text == "Note: ")
    }

    @Test(arguments: [("", "Hi"), ("Dear ", "Dear hi"), ("Dear", "Dear hi"), ("Line\n", "Line\nHi")])
    func separatesFromThePrecedingWord(existing: String, expected: String) {
        let field = Field(existing)
        var typist = Typist()
        typist.begin(in: field)
        typist.update(to: "Hi", in: field)

        #expect(field.text == expected)
    }

    @Test func handlesMultiScalarCharacters() {
        let field = Field()
        var typist = Typist()
        typist.begin(in: field)
        typist.update(to: "Café 👍🏽", in: field)
        typist.update(to: "Café 👍🏽 ok", in: field)
        typist.update(to: "Café", in: field)

        #expect(field.text == "Café")
    }

    @Test func eachUtteranceStartsFresh() {
        let field = Field()
        var typist = Typist()
        typist.begin(in: field)
        typist.update(to: "One.", in: field)
        typist.begin(in: field)
        typist.update(to: "Two.", in: field)

        #expect(field.text == "One. Two.")
    }

    @Test(arguments: [
        ("I went to ", "The store", "I went to the store"),
        ("I went to", "The store", "I went to the store"),
        ("Well, ", "Actually no", "Well, actually no"),
        ("Note: ", "A cat", "Note: a cat"),
        ("Look at ", "Éclair", "Look at éclair"),
    ])
    func lowercasesFirstLetterMidSentence(existing: String, transcript: String, expected: String) {
        let field = Field(existing)
        var typist = Typist()
        typist.begin(in: field)
        typist.update(to: transcript, in: field)

        #expect(field.text == expected)
    }

    @Test(arguments: [
        "I",
        "I think so",
        "I'm going",
        "I’m going",
        "I've seen it",
        "Alice went home",
        "Paris",
        "Google",
        "New York",
        "NASA",
        "NASA launched",
        "OK then",
        "TV show",
    ])
    func keepsCapitalMidSentenceForSpecialWords(transcript: String) {
        let field = Field("Wait, ")
        var typist = Typist()
        typist.begin(in: field)
        typist.update(to: transcript, in: field)

        #expect(field.text == "Wait, " + transcript)
    }

    @Test(arguments: [
        ("", false, "Hello"),
        ("", true, "Hello"),
        ("   ", false, "   Hello"),
        ("Done.", false, "Done. Hello"),
        ("Done. ", false, "Done. Hello"),
        ("Really?", false, "Really? Hello"),
        ("Really? ", false, "Really? Hello"),
        ("Wow!", false, "Wow! Hello"),
        ("Wow! ", false, "Wow! Hello"),
        ("Line\n", false, "Line\nHello"),
        ("Line\n  ", false, "Line\n  Hello"),
    ])
    func keepsRecognisedCasingAtSentenceStart(existing: String, nilWhenEmpty: Bool, expected: String) {
        let field = Field(existing, nilWhenEmpty: nilWhenEmpty)
        var typist = Typist()
        typist.begin(in: field)
        typist.update(to: "Hello", in: field)

        #expect(field.text == expected)
    }

    @Test func retypesOnlyTheChangedPartMidSentence() {
        let field = Field("I want to ")
        var typist = Typist()
        typist.begin(in: field)
        typist.update(to: "Go", in: field)
        typist.update(to: "Go home", in: field)

        #expect(field.text == "I want to go home")
        #expect(field.insertions == ["go", " home"])
        #expect(field.deletions == 0)

        typist.update(to: "Go back", in: field)
        #expect(field.text == "I want to go back")
        #expect(field.deletions == "home".count)
        #expect(field.insertions.last == "back")
    }

    @Test func updatesCasingWhenPartialRevisionChangesFirstWord() {
        let field = Field("Visit ")
        var typist = Typist()
        typist.begin(in: field)
        typist.update(to: "New", in: field)
        #expect(field.text == "Visit new")

        typist.update(to: "New York", in: field)
        #expect(field.text == "Visit New York")
        #expect(field.deletions == "new".count)
        #expect(field.insertions.last == "New York")
    }
}
