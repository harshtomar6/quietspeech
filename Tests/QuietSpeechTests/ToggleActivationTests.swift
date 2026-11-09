import XCTest
@testable import QuietSpeech

final class ToggleActivationTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_000)

    private func doubleTapSession() -> DictationShortcutSessionController {
        var session = DictationShortcutSessionController()
        session.toggleActivationMethod = .doubleTapHold
        return session
    }

    func testSingleTapNeverStartsMicrophone() {
        var session = doubleTapSession()
        XCTAssertEqual(session.handle(.holdActivated, at: origin), [])
        XCTAssertNotNil(session.pendingHoldDeadline)
        XCTAssertEqual(session.handle(.holdDeactivated, at: origin.addingTimeInterval(0.1)), [])
        XCTAssertEqual(session.advanceTime(to: origin.addingTimeInterval(1)), [])
        XCTAssertFalse(session.isActive)
        XCTAssertNil(session.pendingHoldDeadline)
    }

    func testDoubleTapStartsToggleAndSingleTapStops() {
        var session = doubleTapSession()
        _ = session.handle(.holdActivated, at: origin)
        _ = session.handle(.holdDeactivated, at: origin.addingTimeInterval(0.08))
        XCTAssertEqual(session.handle(.holdActivated, at: origin.addingTimeInterval(0.18)), [.start(.toggle)])
        XCTAssertEqual(session.handle(.holdDeactivated, at: origin.addingTimeInterval(0.25)), [])
        XCTAssertEqual(session.activeMode, .toggle)
        XCTAssertNil(session.pendingHoldDeadline)
        XCTAssertEqual(session.advanceTime(to: origin.addingTimeInterval(1)), [])
        XCTAssertEqual(session.handle(.holdActivated, at: origin.addingTimeInterval(2)), [.stop])
        XCTAssertEqual(session.handle(.holdDeactivated, at: origin.addingTimeInterval(2.1)), [])
        XCTAssertFalse(session.isActive)
    }

    func testHoldingStillStartsAndStopsDictation() {
        var session = doubleTapSession()
        XCTAssertEqual(session.handle(.holdActivated, at: origin), [])
        XCTAssertEqual(session.advanceTime(to: origin.addingTimeInterval(0.2)), [])
        XCTAssertEqual(session.advanceTime(to: origin.addingTimeInterval(0.31)), [.start(.hold)])
        XCTAssertEqual(session.advanceTime(to: origin.addingTimeInterval(0.4)), [])
        XCTAssertEqual(session.handle(.holdDeactivated, at: origin.addingTimeInterval(0.5)), [.stop])
        // A normal hold must not count as the first half of a double-tap.
        XCTAssertEqual(session.handle(.holdActivated, at: origin.addingTimeInterval(0.6)), [])
        XCTAssertNil(session.activeMode)
    }

    func testSlowTapsAndLateTimersCannotStartToggle() {
        var session = doubleTapSession()
        _ = session.handle(.holdActivated, at: origin)
        _ = session.handle(.holdDeactivated, at: origin.addingTimeInterval(0.1))
        XCTAssertEqual(session.handle(.holdActivated, at: origin.addingTimeInterval(0.6)), [])
        _ = session.handle(.holdDeactivated, at: origin.addingTimeInterval(0.7))
        XCTAssertEqual(session.advanceTime(to: origin.addingTimeInterval(1)), [])
        XCTAssertFalse(session.isActive)

        // If the UI was busy, a long press released before its timer is
        // delivered must neither start later nor become a quick tap.
        session.reset()
        _ = session.handle(.holdActivated, at: origin)
        _ = session.handle(.holdDeactivated, at: origin.addingTimeInterval(0.5))
        XCTAssertEqual(session.advanceTime(to: origin.addingTimeInterval(0.51)), [])
        XCTAssertEqual(session.handle(.holdActivated, at: origin.addingTimeInterval(0.6)), [])
    }

    func testExternalStopAndSettingsChangeClearPendingTaps() {
        var session = doubleTapSession()
        _ = session.handle(.holdActivated, at: origin)
        _ = session.handle(.holdDeactivated, at: origin.addingTimeInterval(0.1))
        session.sessionDidStopExternally()
        XCTAssertEqual(session.handle(.holdActivated, at: origin.addingTimeInterval(0.2)), [])
        session.reset()
        XCTAssertEqual(session.advanceTime(to: origin.addingTimeInterval(1)), [])
    }

    func testSeparateShortcutAndLatchKeepExistingBehavior() {
        var session = DictationShortcutSessionController()
        XCTAssertEqual(session.handle(.holdActivated), [.start(.hold)])
        XCTAssertEqual(session.handle(.toggleActivated), [.switchedToToggle])
        XCTAssertEqual(session.handle(.holdDeactivated), [])
        XCTAssertEqual(session.handle(.toggleDeactivated), [])
        XCTAssertEqual(session.handle(.toggleActivated), [.stop])
        XCTAssertEqual(session.handle(.toggleActivated), [.start(.toggle)])
        XCTAssertEqual(session.handle(.toggleActivated), [.stop])
    }

    func testLegacySettingsKeepSeparateShortcutAndNewChoiceRoundTrips() throws {
        let original = ShortcutConfiguration.defaultConfiguration
        let encoded = try JSONEncoder().encode(original)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "toggleActivationMethod")
        let decoded = try JSONDecoder().decode(ShortcutConfiguration.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.toggleActivationMethod, .shortcut)

        let doubleTap = decoded.usingToggleActivation(.doubleTapHold)
        let restored = try JSONDecoder().decode(ShortcutConfiguration.self, from: JSONEncoder().encode(doubleTap))
        XCTAssertEqual(restored, doubleTap)
        XCTAssertEqual(restored.replacing(.hold, with: ShortcutPreset.rightOption.binding).toggleActivationMethod, .doubleTapHold)
        XCTAssertEqual(restored.usingToggleActivation(.shortcut).toggle, original.toggle)
    }

    func testDoubleTapUsesCurrentHoldBindingAndDisablesDormantShortcut() {
        let configuration = ShortcutConfiguration(
            hold: ShortcutPreset.rightOption.binding,
            toggle: ShortcutPreset.f5.binding,
            toggleActivationMethod: .doubleTapHold
        )
        var matcher = ShortcutMatcher(configuration: configuration)
        var session = doubleTapSession()
        XCTAssertEqual(matcher.handle(.keyChanged(keyCode: 96, isDown: true)), .passthrough)
        XCTAssertEqual(matcher.drainEvents(), [])
        for (offset, down) in [(0.0, true), (0.08, false), (0.18, true), (0.25, false)] {
            XCTAssertEqual(matcher.handle(.modifierChanged(keyCode: 61, isDown: down)), .consume)
            for event in matcher.drainEvents() {
                let actions = session.handle(event, at: origin.addingTimeInterval(offset))
                XCTAssertEqual(actions, offset == 0.18 ? [.start(.toggle)] : [])
            }
        }
        XCTAssertEqual(session.activeMode, .toggle)
        XCTAssertTrue(configuration.summary.contains("Double-tap Right Option"))
        XCTAssertFalse(configuration.summary.contains("F5"))

        let overlapping = configuration.replacing(.toggle, with: configuration.hold)
        XCTAssertTrue(overlapping.conflictingRoles.isEmpty)
        XCTAssertFalse(overlapping.usingToggleActivation(.shortcut).conflictingRoles.isEmpty)
    }

    func testDoubleTapRequiresEnabledHoldKey() {
        let configuration = ShortcutConfiguration(
            hold: .disabled, toggle: ShortcutPreset.f5.binding,
            toggleActivationMethod: .doubleTapHold
        )
        XCTAssertTrue(configuration.isDisabled)
        XCTAssertFalse(configuration.toggleModeEnabled)
        XCTAssertEqual(configuration.summary, "Disabled")
    }
}
