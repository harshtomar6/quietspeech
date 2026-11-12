import Foundation
import XCTest
@testable import QuietSpeech

final class MediaPlaybackControllerTests: XCTestCase {
    @MainActor
    func testDisabledDoesNotContactMediaService() async {
        let controller = MediaPlaybackController(readPlayback: { _ in
            XCTFail("Disabled setting must not query the player")
        }, sendCommand: { _ in
            XCTFail("Disabled setting must not send a command")
            return true
        })
        let sent = await controller.pauseIfEnabled(false, session: 1)
        let resumed = await controller.resumeIfNeeded(for: 1)
        XCTAssertFalse(sent)
        XCTAssertFalse(resumed)
    }

    @MainActor
    func testPlayingMediaResumesExactlyOnceAfterFinishing() async {
        let player = Player(playing: true)
        let controller = MediaPlaybackController(readPlayback: player.read, sendCommand: player.send)
        let paused = await controller.pauseIfEnabled(true, session: 1)
        XCTAssertTrue(paused)
        XCTAssertEqual(player.commands, [1], "Keep media paused through transcription")
        let resumed = await controller.resumeIfNeeded(for: 1)
        let repeated = await controller.resumeIfNeeded(for: 1)
        XCTAssertTrue(resumed)
        XCTAssertFalse(repeated)
        XCTAssertEqual(player.commands, [1, 0], "Never send play/pause toggle (2)")
    }

    @MainActor
    func testAlreadyPausedMediaIsNeverStarted() async {
        let player = Player(playing: false)
        let controller = MediaPlaybackController(readPlayback: player.read, sendCommand: player.send)
        _ = await controller.pauseIfEnabled(true, session: 1)
        let resumed = await controller.resumeIfNeeded(for: 1)
        XCTAssertFalse(resumed)
        XCTAssertEqual(player.commands, [1])
    }

    @MainActor
    func testUnknownPlaybackStateStillPausesButNeverResumes() async {
        let player = Player(playing: true)
        let controller = MediaPlaybackController(readPlayback: { $0(nil) }, sendCommand: player.send)
        _ = await controller.pauseIfEnabled(true, session: 1)
        let resumed = await controller.resumeIfNeeded(for: 1)
        XCTAssertFalse(resumed)
        XCTAssertEqual(player.commands, [1])
    }

    @MainActor
    func testFailedPauseDoesNotAuthorizePlay() async {
        let player = Player(playing: true)
        let controller = MediaPlaybackController(readPlayback: player.read) { _ in false }
        let paused = await controller.pauseIfEnabled(true, session: 1)
        let resumed = await controller.resumeIfNeeded(for: 1)
        XCTAssertFalse(paused)
        XCTAssertFalse(resumed)
    }

    @MainActor
    func testChangedMediaAppIsNotStarted() async {
        let player = Player(playing: true)
        let controller = MediaPlaybackController(readPlayback: player.read, sendCommand: player.send)
        _ = await controller.pauseIfEnabled(true, session: 1)
        player.setState(playerID: 99, playing: false)
        let resumed = await controller.resumeIfNeeded(for: 1)
        XCTAssertFalse(resumed)
        XCTAssertEqual(player.commands, [1])
    }

    @MainActor
    func testManualResumeIsNotRepeated() async {
        let player = Player(playing: true)
        let controller = MediaPlaybackController(readPlayback: player.read, sendCommand: player.send)
        _ = await controller.pauseIfEnabled(true, session: 1)
        player.setState(playerID: 42, playing: true)
        let resumed = await controller.resumeIfNeeded(for: 1)
        XCTAssertFalse(resumed)
        XCTAssertEqual(player.commands, [1])
    }

    @MainActor
    func testOldTranscriptionCannotResumeDuringNewRecording() async {
        let player = Player(playing: true)
        let controller = MediaPlaybackController(readPlayback: player.read, sendCommand: player.send)
        _ = await controller.pauseIfEnabled(true, session: 1)
        _ = await controller.pauseIfEnabled(true, session: 2)
        let stale = await controller.resumeIfNeeded(for: 1)
        XCTAssertFalse(stale)
        XCTAssertEqual(player.commands, [1, 1])
        let current = await controller.resumeIfNeeded(for: 2)
        XCTAssertTrue(current, "The new session inherits ownership of the existing pause")
        XCTAssertEqual(player.commands, [1, 1, 0])
    }

    @MainActor
    func testDisabledNewSessionStillReleasesInheritedPause() async {
        let player = Player(playing: true)
        let controller = MediaPlaybackController(readPlayback: player.read, sendCommand: player.send)
        _ = await controller.pauseIfEnabled(true, session: 1)
        _ = await controller.pauseIfEnabled(false, session: 2)
        let stale = await controller.resumeIfNeeded(for: 1)
        let current = await controller.resumeIfNeeded(for: 2)
        XCTAssertFalse(stale)
        XCTAssertTrue(current)
        XCTAssertEqual(player.commands, [1, 0])
    }

    @MainActor
    func testMissingStateReplyDoesNotBlockPauseOrAuthorizeResume() async {
        let player = Player(playing: true)
        let controller = MediaPlaybackController(timeout: 0.05, stateTimeout: 0.05, readPlayback: { _ in }, sendCommand: player.send)
        let paused = await controller.pauseIfEnabled(true, session: 1)
        let resumed = await controller.resumeIfNeeded(for: 1)
        XCTAssertTrue(paused)
        XCTAssertFalse(resumed)
        XCTAssertEqual(player.commands, [1])
    }

    @MainActor
    func testLatePauseReplyCannotAuthorizeResume() async {
        let player = Player(playing: true)
        let unblock = DispatchSemaphore(value: 0)
        let finished = expectation(description: "Late service response")
        let controller = MediaPlaybackController(timeout: 0.05, readPlayback: player.read) { _ in
            unblock.wait()
            finished.fulfill()
            return true
        }
        let paused = await controller.pauseIfEnabled(true, session: 1)
        unblock.signal()
        await fulfillment(of: [finished], timeout: 1)
        let resumed = await controller.resumeIfNeeded(for: 1)
        XCTAssertFalse(paused)
        XCTAssertFalse(resumed)
    }

    private final class Player: @unchecked Sendable {
        private let lock = NSLock()
        private var state: MediaPlaybackController.PlaybackState
        private var recorded: [Int32] = []

        init(playing: Bool) { state = .init(playerID: 42, isPlaying: playing) }

        var commands: [Int32] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }

        func setState(playerID: Int32, playing: Bool) {
            lock.lock()
            state = .init(playerID: playerID, isPlaying: playing)
            lock.unlock()
        }

        @Sendable func read(_ finish: @escaping @Sendable (MediaPlaybackController.PlaybackState?) -> Void) {
            lock.lock()
            let value = state
            lock.unlock()
            finish(value)
        }

        @Sendable func send(_ command: Int32) -> Bool {
            lock.lock()
            recorded.append(command)
            state = .init(playerID: state.playerID, isPlaying: command == 0)
            lock.unlock()
            return true
        }
    }
}
