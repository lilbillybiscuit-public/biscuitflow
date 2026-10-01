import XCTest
@testable import BiscuitFlow

final class TextProcessorTests: XCTestCase {
    func testStripsFillers() {
        XCTAssertEqual(TextProcessor.stripFillers("Um, so we should ship it."), "So we should ship it.")
        XCTAssertEqual(TextProcessor.stripFillers("I think, uh, we should, um, wait."), "I think, we should, wait.")
        XCTAssertEqual(TextProcessor.stripFillers("Hmm. Okay."), "Okay.")
        // Real words that merely start with filler letters survive.
        XCTAssertEqual(TextProcessor.stripFillers("The umbrella is under the hummingbird."), "The umbrella is under the hummingbird.")
        XCTAssertEqual(TextProcessor.stripFillers("Uhh, ahh, errm"), "")
    }

    func testReplacementsAreWholeWordAndCaseInsensitive() {
        var p = TextProcessor()
        p.replacements = [DictionaryEntry(word: "BiscuitFlow", spokenForm: "h flow"),
                          DictionaryEntry(word: "Kubernetes")] // bias-only, not a replacement
        XCTAssertEqual(p.applyReplacements("I love H flow and h flows."), "I love BiscuitFlow and h flows.")
        XCTAssertEqual(p.applyReplacements("kubernetes"), "kubernetes")
    }

    func testSnippetExpandsOnlyWholeUtterance() {
        var p = TextProcessor()
        p.snippets = [Snippet(trigger: "my email", expansion: "me@example.com")]
        XCTAssertEqual(p.process("My email.", context: nil), "me@example.com")
        XCTAssertEqual(p.process("Send it to my email please.", context: nil), "Send it to my email please.")
    }

    func testFitToCaret() {
        // Empty field / start of text: unchanged.
        XCTAssertEqual(TextProcessor.fitToCaret("Hello there.", before: ""), "Hello there.")
        XCTAssertEqual(TextProcessor.fitToCaret("Hello there.", before: nil), "Hello there.")
        // After a finished sentence: add a space, keep the capital.
        XCTAssertEqual(TextProcessor.fitToCaret("Next one.", before: "Done."), " Next one.")
        // Mid-sentence: add a space and lowercase.
        XCTAssertEqual(TextProcessor.fitToCaret("Maybe tomorrow.", before: "I think"), " maybe tomorrow.")
        XCTAssertEqual(TextProcessor.fitToCaret("Maybe tomorrow.", before: "I think "), "maybe tomorrow.")
        // Keep "I" and acronyms.
        XCTAssertEqual(TextProcessor.fitToCaret("I agree.", before: "and"), " I agree.")
        XCTAssertEqual(TextProcessor.fitToCaret("NASA called.", before: "then"), " NASA called.")
        // After a newline: no space.
        XCTAssertEqual(TextProcessor.fitToCaret("New line.", before: "x\n"), "New line.")
        // Starting with punctuation: no space.
        XCTAssertEqual(TextProcessor.fitToCaret(", right?", before: "ok"), ", right?")
    }

    func testTranscriberCleanStripsMarkup() {
        XCTAssertEqual(Transcriber.clean("language English<asr_text>Hello world.<|im_end|>"), "Hello world.")
        XCTAssertEqual(Transcriber.clean("  plain  "), "plain")
    }

    func testSpeechGate() {
        XCTAssertFalse(DictationController.containsSpeech([Float](repeating: 0.0005, count: 16000)))
        let tone = (0..<16000).map { Float(sin(Double($0) * 0.1) * 0.1) }
        XCTAssertTrue(DictationController.containsSpeech(tone))
    }

    @MainActor
    func testStats() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = Store(directory: dir)
        let now = Date()
        store.history = [
            HistoryItem(date: now, text: "one two three four", rawText: "", audioSeconds: 2, inferenceSeconds: 0.1),
            HistoryItem(date: now.addingTimeInterval(-86400), text: "five six", rawText: "", audioSeconds: 1, inferenceSeconds: 0.1),
            HistoryItem(date: now.addingTimeInterval(-3 * 86400), text: "seven", rawText: "", audioSeconds: 3, inferenceSeconds: 0.1),
        ]
        XCTAssertEqual(store.totalWords, 7)
        XCTAssertEqual(store.wordsPerMinute, 70)
        XCTAssertEqual(store.streakDays, 2)
        // Round-trips through disk.
        XCTAssertEqual(Store(directory: dir).history.count, 3)
    }
}
