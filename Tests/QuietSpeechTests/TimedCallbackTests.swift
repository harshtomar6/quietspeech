import XCTest
@testable import QuietSpeech

final class TimedCallbackTests: XCTestCase {
    @MainActor
    func testImmediateResponseReturnsItsValue() async {
        let result = await TimedCallback.run(timeout: 1, fallback: -1) { finish in finish(42) }
        XCTAssertEqual(result, 42)
    }

    @MainActor
    func testMissingResponseTimesOutAndLeavesMainQueueResponsive() async {
        let mainQueueResponsive = expectation(description: "Main queue remains responsive")
        var lateResponse: (@Sendable (Int) -> Void)?
        let result = await TimedCallback.run(timeout: 0.05, fallback: -1) { finish in
            lateResponse = finish
            DispatchQueue.main.async { mainQueueResponsive.fulfill() }
        }
        XCTAssertEqual(result, -1)
        await fulfillment(of: [mainQueueResponsive], timeout: 1)
        lateResponse?(42) // Must be ignored rather than resuming twice.
    }

    @MainActor
    func testSpellingResultsMapToWordsUsingUTF16Ranges() {
        let results = [NSTextCheckingResult.spellCheckingResult(range: NSRange(location: 5, length: 5))]
        XCTAssertEqual(
            SpellingDictionary.knowledge(for: ["café", "priya", "hello"], results: results),
            ["café": true, "priya": false, "hello": true]
        )
    }
}
