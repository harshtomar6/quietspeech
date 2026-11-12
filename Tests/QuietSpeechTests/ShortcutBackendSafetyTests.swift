import AppKit
import XCTest
@testable import QuietSpeech

/// These feed unposted events directly into the real callback processor.
/// No global tap is installed and no system permission is revoked.
final class ShortcutBackendSafetyTests: XCTestCase {
    private func modifier(_ code: UInt16, flags: CGEventFlags) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true))
        event.type = .flagsChanged
        event.flags = flags
        return event
    }

    func testTimeoutCannotLeaveFnHeldAndSwallowOrdinaryCommand() throws {
        let backend = ShortcutBackend()
        let fn = try modifier(63, flags: .maskSecondaryFn)
        XCTAssertTrue(backend.process(type: .flagsChanged, event: fn) == nil)
        _ = backend.process(type: .tapDisabledByTimeout, event: fn)
        // Fn was released while the tap was disabled, so no release arrived.
        let command = try modifier(55, flags: .maskCommand)
        XCTAssertTrue(backend.process(type: .flagsChanged, event: command) != nil)
    }

    func testUserDisabledStreamStaysPassThrough() throws {
        let backend = ShortcutBackend()
        let fn = try modifier(63, flags: .maskSecondaryFn)
        _ = backend.process(type: .flagsChanged, event: fn)
        _ = backend.process(type: .tapDisabledByUserInput, event: fn)
        XCTAssertTrue(backend.process(type: .flagsChanged, event: fn) != nil)
        XCTAssertTrue(backend.process(type: .flagsChanged, event: try modifier(55, flags: .maskCommand)) != nil)
    }

    @MainActor
    func testStoppingStreamCannotKeepAnOldModifierBindingActive() throws {
        let backend = ShortcutBackend()
        _ = backend.process(type: .flagsChanged, event: try modifier(63, flags: .maskSecondaryFn))
        backend.stopTap()
        XCTAssertTrue(backend.process(type: .flagsChanged, event: try modifier(55, flags: .maskCommand)) != nil)
    }

    @MainActor
    func testQueuedActivationIsDiscardedAfterStreamIsDisabled() async throws {
        let backend = ShortcutBackend()
        var delivered: [ShortcutEvent] = []
        backend.onEvent = { event, _ in delivered.append(event) }
        let fn = try modifier(63, flags: .maskSecondaryFn)
        _ = backend.process(type: .flagsChanged, event: fn)
        _ = backend.process(type: .tapDisabledByUserInput, event: fn)
        let drained = expectation(description: "Main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 1)
        XCTAssertEqual(delivered, [])
    }

    func testKeyboardCallbackDoesNotWaitForConfigurationLock() throws {
        try assertCallbackDoesNotWait(type: .keyDown)
    }

    func testMouseEventPassesThroughEvenWhenConfigurationIsLocked() throws {
        try assertCallbackDoesNotWait(type: .leftMouseDown)
    }

    func testSyntheticTypingCannotActivateShortcuts() throws {
        let backend = ShortcutBackend()
        let source = try XCTUnwrap(KeyboardEventSource.make())
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: 63, keyDown: true))
        event.flags = .maskSecondaryFn
        XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), KeyboardEventSource.marker)
        XCTAssertTrue(backend.process(type: .flagsChanged, event: event) != nil)
        XCTAssertTrue(backend.process(type: .flagsChanged, event: try modifier(55, flags: .maskCommand)) != nil)
    }

    func testSyntheticEventSourcesExplicitlyPermitAllHardwareInput() throws {
        let source = try XCTUnwrap(KeyboardEventSource.make())
        XCTAssertEqual(source.localEventsSuppressionInterval, 0)
        let hardware: CGEventFilterMask = [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents]
        XCTAssertEqual(source.getLocalEventsFilterDuringSuppressionState(.eventSuppressionStateSuppressionInterval), hardware)
        XCTAssertEqual(source.getLocalEventsFilterDuringSuppressionState(.eventSuppressionStateRemoteMouseDrag), hardware)
        XCTAssertNotEqual(source.sourceStateID, .combinedSessionState)
    }

    func testCancelledTapCannotBeEnabledByLateThreadStartup() {
        let lifecycle = ShortcutTapLifecycle()
        var enabled = false
        lifecycle.stop { enabled = false }
        XCTAssertFalse(lifecycle.start { enabled = true })
        XCTAssertFalse(enabled)
    }

    func testStaleTapCallbackCannotConsumeKeysFromANewerStream() throws {
        let backend = ShortcutBackend()
        let fn = try modifier(63, flags: .maskSecondaryFn)
        XCTAssertTrue(backend.process(type: .flagsChanged, event: fn, tapToken: 99) != nil)
        XCTAssertTrue(backend.process(type: .flagsChanged, event: fn, tapToken: 0) == nil)
    }

    func testContentionForgetsModifiersBeforeMatchingNextKey() throws {
        let lock = NSLock()
        let backend = ShortcutBackend(lock: lock)
        _ = backend.process(type: .flagsChanged, event: try modifier(63, flags: .maskSecondaryFn))
        let command = try modifier(55, flags: .maskCommand)
        lock.lock()
        let passed = backend.process(type: .flagsChanged, event: command) != nil
        lock.unlock()
        XCTAssertTrue(passed)
        XCTAssertTrue(backend.process(type: .flagsChanged, event: command) != nil)
    }

    func testStoppingAnEnabledLifecyclePreventsAnyLaterEnable() {
        let lifecycle = ShortcutTapLifecycle()
        var enabled = false
        XCTAssertTrue(lifecycle.start { enabled = true })
        XCTAssertTrue(enabled)
        lifecycle.stop { enabled = false }
        XCTAssertFalse(lifecycle.start { enabled = true })
        XCTAssertFalse(enabled)
    }

    @MainActor
    func testMissingAccessibilityKeepsListenerStoppedWithoutCreatingGlobalTap() {
        let backend = ShortcutBackend(permissionCheck: { false })
        var message: String?
        backend.onTapUnavailable = { message = $0 }
        XCTAssertFalse(backend.ensureTap())
        XCTAssertFalse(backend.tapActive)
        XCTAssertNotNil(message)
    }

    private func assertCallbackDoesNotWait(type: CGEventType) throws {
        let lock = NSLock()
        let backend = ShortcutBackend(lock: lock)
        let event = try XCTUnwrap(CGEvent(source: nil))
        let returned = expectation(description: "Callback returned")
        let finished = expectation(description: "Worker finished")
        lock.lock()
        DispatchQueue.global(qos: .userInitiated).async {
            XCTAssertTrue(backend.process(type: type, event: event) != nil)
            returned.fulfill()
            finished.fulfill()
        }
        let result = XCTWaiter.wait(for: [returned], timeout: 0.1)
        lock.unlock()
        XCTAssertEqual(result, .completed, "An input callback must pass events through without waiting")
        wait(for: [finished], timeout: 1)
    }
}
