import AppKit
import Observation
import Sparkle
import XCTest
@testable import QuietSpeech

final class UpdateControllerTests: XCTestCase {
    @MainActor
    private func makeController() throws -> (UpdateController, SPUUpdater) {
        _ = NSApplication.shared
        let suite = "QuietSpeech.UpdateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let controller = UpdateController(startingUpdater: false, defaults: defaults, currentBuild: "9")
        return (controller, try XCTUnwrap(controller.controller?.updater))
    }

    private func state() throws -> SPUUserUpdateState {
        try XCTUnwrap(SPUUserUpdateState(coder: StateDecoder()))
    }

    @MainActor
    func testStartsWithoutUpdateReminder() throws {
        let (controller, _) = try makeController()
        XCTAssertFalse(controller.isUpdateAvailable)
    }

    @MainActor
    func testReminderSurvivesRelaunchButNotInstallingANewBuild() throws {
        let suite = "QuietSpeech.UpdateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = UpdateController(startingUpdater: false, defaults: defaults, currentBuild: "9")
        first.updater(try XCTUnwrap(first.controller?.updater), didFindValidUpdate: SUAppcastItem.empty())
        let relaunched = UpdateController(startingUpdater: false, defaults: defaults, currentBuild: "9")
        XCTAssertTrue(relaunched.isUpdateAvailable)
        let installed = UpdateController(startingUpdater: false, defaults: defaults, currentBuild: "10")
        XCTAssertFalse(installed.isUpdateAvailable)
    }

    @MainActor
    func testValidUpdateNotifiesObserversAndNoUpdateClearsReminder() throws {
        let (controller, updater) = try makeController()
        let changed = expectation(description: "Menu-bar availability changes")
        withObservationTracking {
            _ = controller.isUpdateAvailable
        } onChange: {
            changed.fulfill()
        }
        let delegate: SPUUpdaterDelegate = controller
        delegate.updater?(updater, didFindValidUpdate: SUAppcastItem.empty())
        XCTAssertTrue(controller.isUpdateAvailable)
        wait(for: [changed], timeout: 1)
        delegate.updaterDidNotFindUpdate?(updater)
        XCTAssertFalse(controller.isUpdateAvailable)
    }

    @MainActor
    func testDismissingUpdateKeepsReminderButSkippingClearsIt() throws {
        let (controller, updater) = try makeController()
        let item = SUAppcastItem.empty()
        let delegate: SPUUpdaterDelegate = controller
        delegate.updater?(updater, didFindValidUpdate: item)
        delegate.updater?(updater, userDidMake: .dismiss, forUpdate: item, state: try state())
        XCTAssertTrue(controller.isUpdateAvailable)
        delegate.updater?(updater, userDidMake: .install, forUpdate: item, state: try state())
        XCTAssertTrue(controller.isUpdateAvailable)
        delegate.updater?(updater, userDidMake: .skip, forUpdate: item, state: try state())
        XCTAssertFalse(controller.isUpdateAvailable)
    }

    @MainActor
    func testStagedUpdateAlsoSetsReminderAndScheduledChecksStayPassive() throws {
        let (controller, _) = try makeController()
        let item = SUAppcastItem.empty()
        let delegate: SPUStandardUserDriverDelegate = controller
        XCTAssertEqual(delegate.supportsGentleScheduledUpdateReminders, true)
        XCTAssertEqual(delegate.standardUserDriverShouldHandleShowingScheduledUpdate?(item, andInImmediateFocus: false), false)
        XCTAssertEqual(delegate.standardUserDriverShouldHandleShowingScheduledUpdate?(item, andInImmediateFocus: true), false)
        delegate.standardUserDriverWillHandleShowingUpdate?(false, forUpdate: item, state: try state())
        XCTAssertTrue(controller.isUpdateAvailable)
    }

    private final class StateDecoder: NSCoder {
        override var allowsKeyedCoding: Bool { true }
        override func decodeInteger(forKey key: String) -> Int { 0 }
        override func decodeBool(forKey key: String) -> Bool { false }
    }
}
