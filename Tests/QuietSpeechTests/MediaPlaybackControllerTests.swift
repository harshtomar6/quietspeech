import Foundation
import XCTest
@testable import QuietSpeech

final class MediaPlaybackControllerTests: XCTestCase {
    @MainActor
    func testDisabledDoesNotSendAnyCommand() async {
        let controller = MediaPlaybackController { _ in
            XCTFail("Disabled media pausing must not contact the player")
            return true
        }
        let sent = await controller.pauseIfEnabled(false)
        XCTAssertFalse(sent)
    }

    @MainActor
    func testEnabledSendsPauseInsteadOfPlayOrToggle() async {
        let paused = expectation(description: "One pause request")
        paused.assertForOverFulfill = true
        let controller = MediaPlaybackController { command in
            XCTAssertEqual(command, 1)
            paused.fulfill()
            return true
        }
        let sent = await controller.pauseIfEnabled(true)
        XCTAssertTrue(sent)
        await fulfillment(of: [paused], timeout: 1)
    }

    @MainActor
    func testUnavailableMediaServiceIsHarmless() async {
        let controller = MediaPlaybackController { _ in false }
        let sent = await controller.pauseIfEnabled(true)
        XCTAssertFalse(sent)
    }

    @MainActor
    func testUnresponsiveServiceDoesNotBlockDictationStartup() async {
        let unblock = DispatchSemaphore(value: 0)
        let finished = expectation(description: "Late service response")
        let controller = MediaPlaybackController(timeout: 0.05) { _ in
            unblock.wait()
            finished.fulfill()
            return true
        }
        let sent = await controller.pauseIfEnabled(true)
        XCTAssertFalse(sent)
        unblock.signal()
        await fulfillment(of: [finished], timeout: 1)
    }
}
