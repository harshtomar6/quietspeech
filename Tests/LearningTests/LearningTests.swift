import XCTest
@testable import Learning

final class ScreenTermsTests: XCTestCase {
    private let dictionary: Set<String> = [
        "hi", "thanks", "for", "the", "numbers", "can", "you", "ask", "about", "polar",
        "checkout", "we", "shipped", "today", "i'm", "sure", "meeting", "with", "on", "monday",
        "channel", "info", "created", "notes",
    ]

    private func extract(_ text: String) -> [String] {
        ScreenTerms.extract(from: text, isKnownWord: { self.dictionary.contains($0) })
    }

    func testFindsNamesAndJargon() {
        let terms = extract("Hi Priya, thanks for the numbers. Can you ask Polar about the QuietSpeech checkout? We shipped the API today.")
        XCTAssertEqual(Set(terms), ["Priya", "Polar", "QuietSpeech", "API"])
    }

    func testSkipsDictionaryWordsThatOnlyOpenSentences() {
        XCTAssertEqual(extract("Thanks. Sure. Meeting on Monday."), [])
    }

    func testSkipsTitleCaseLabels() {
        XCTAssertEqual(extract("Channel Info\nCreated Today\nMeeting Notes With Priya"), ["Priya"])
    }

    func testPossessivesAndContractions() {
        XCTAssertEqual(extract("I'm sure Priya's numbers are right."), ["Priya"])
    }

    func testRanksDistinctiveTermsFirst() {
        let terms = extract("ask Polar about QuietSpeech")
        XCTAssertEqual(terms.first, "QuietSpeech")
    }
}

final class CorrectionDetectorTests: XCTestCase {
    private let dictionary: Set<String> = [
        "send", "the", "numbers", "to", "please", "korea", "their", "there", "is", "a", "it",
        "quiet", "speech", "jet", "hub", "on", "push", "polar", "ask", "about", "pricing", "we",
        "use", "utilize", "today", "can", "you", "and",
    ]

    private func corrections(_ original: String, _ edited: String) -> [Correction] {
        CorrectionDetector.corrections(original: original, edited: edited, isKnownWord: { self.dictionary.contains($0) })
    }

    func testMisheardNameBecomesReplacement() {
        XCTAssertEqual(corrections("Send the numbers to Pria, please.", "Send the numbers to Priya, please."),
                       [Correction(heard: "Pria", corrected: "Priya", addsReplacement: true, terms: ["Priya"])])
    }

    func testRealWordIsOnlyVocabulary() {
        XCTAssertEqual(corrections("Send the numbers to Korea.", "Send the numbers to Kariya."),
                       [Correction(heard: "Korea", corrected: "Kariya", addsReplacement: false, terms: ["Kariya"])])
    }

    func testJoinedProductName() {
        XCTAssertEqual(corrections("It is on quiet speech today.", "It is on QuietSpeech today."),
                       [Correction(heard: "quiet speech", corrected: "QuietSpeech", addsReplacement: true, terms: ["QuietSpeech"])])
    }

    func testMultiWordSoundAlike() {
        XCTAssertEqual(corrections("Push it to jet hub.", "Push it to GitHub."),
                       [Correction(heard: "jet hub", corrected: "GitHub", addsReplacement: true, terms: ["GitHub"])])
    }

    func testSpokenAcronym() {
        XCTAssertEqual(corrections("Can we use the ERLMAP?", "Can we use the LLM API?"),
                       [Correction(heard: "ERLMAP", corrected: "LLM API", addsReplacement: true, terms: ["LLM", "API"])])
    }

    func testMidSentenceCapitalization() {
        XCTAssertEqual(corrections("Ask polar about pricing.", "Ask Polar about pricing."),
                       [Correction(heard: "polar", corrected: "Polar", addsReplacement: false, terms: ["Polar"])])
    }

    func testIgnoresSentenceCapitalization() {
        XCTAssertEqual(corrections("polar is there.", "Polar is there."), [])
    }

    func testIgnoresGrammarFixes() {
        XCTAssertEqual(corrections("It is their.", "It is there."), [])
    }

    func testIgnoresRewording() {
        XCTAssertEqual(corrections("We utilize it today.", "We use it today."), [])
        XCTAssertEqual(corrections("Can you send the numbers?", "Send the numbers."), [])
    }

    func testIgnoresTypingMore() {
        XCTAssertEqual(corrections("Send the numbers.", "Send the numbers. Thanks Priya!"), [])
    }
}

final class InsertionAnchorTests: XCTestCase {
    func testFindsEditedSpanBetweenNeighbours() throws {
        let before = "Earlier line.\nSend the numbers to Pria, please.\nLater line."
        let anchor = try XCTUnwrap(InsertionAnchor(inserted: "Send the numbers to Pria, please.", in: before, caret: 47))
        let after = "Earlier line.\nSend the numbers to Priya, please.\nLater line."
        XCTAssertEqual(anchor.span(in: after), "Send the numbers to Priya, please.")
    }

    func testEmptyFieldTakesWholeValue() throws {
        let anchor = try XCTUnwrap(InsertionAnchor(inserted: "Hi Pria", in: "Hi Pria", caret: 7))
        XCTAssertEqual(anchor.span(in: "Hi Priya"), "Hi Priya")
    }

    func testPicksCopyNearestCaret() throws {
        let value = "ok then. ok then."
        let anchor = try XCTUnwrap(InsertionAnchor(inserted: "ok then.", in: value, caret: 17))
        XCTAssertEqual(anchor.span(in: "ok then. OK then!"), "OK then!")
    }

    func testClearedFieldHasNoSpan() throws {
        let anchor = try XCTUnwrap(InsertionAnchor(inserted: "Hello", in: "Dear team,\nHello\nBye", caret: 16))
        XCTAssertNil(anchor.span(in: ""))
    }

    func testMissingInsertionHasNoAnchor() {
        XCTAssertNil(InsertionAnchor(inserted: "Hello", in: "Goodbye", caret: nil))
    }
}

final class CorrectionTallyTests: XCTestCase {
    func testLearnsOnSecondSighting() {
        var tally = CorrectionTally()
        let correction = Correction(heard: "Pria", corrected: "Priya", addsReplacement: true, terms: ["Priya"])
        XCTAssertEqual(tally.record(correction), .init())
        XCTAssertEqual(tally.record(correction), .init(terms: ["Priya"], replacement: true))
        XCTAssertEqual(tally.record(correction), .init(), "a learned correction starts over")
    }

    func testTermAddsUpAcrossDifferentMishearings() {
        let dictionary: Set<String> = ["can", "we", "use", "the", "do", "you", "know"]
        let first = CorrectionDetector.corrections(original: "Can we use the LMAK?", edited: "Can we use the LLM API?",
                                                   isKnownWord: { dictionary.contains($0) })
        let second = CorrectionDetector.corrections(original: "Do you know we can use LMAPIs?", edited: "Do you know we can use LLM APIs?",
                                                    isKnownWord: { dictionary.contains($0) })
        var tally = CorrectionTally()
        XCTAssertEqual(first.map { tally.record($0) }, [.init()])
        XCTAssertEqual(second.map { tally.record($0) }, [.init(terms: ["LLM", "API"], replacement: false)])
    }
}
