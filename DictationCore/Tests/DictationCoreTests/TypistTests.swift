import Foundation
import Testing
@testable import DictationCore

/// A text field that also counts keystrokes, to check how much gets retyped.
private final class Field: TextTarget {
    let fieldID = UUID()
    var text: String
    var deletions = 0
    var insertions: [String] = []

    init(_ text: String = "") { self.text = text }

    var textBeforeCursor: String? { text }
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

    @Test(arguments: [("", "Hi"), ("Dear ", "Dear Hi"), ("Dear", "Dear Hi"), ("Line\n", "Line\nHi")])
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
}
