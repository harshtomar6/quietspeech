import XCTest
@testable import QuietSpeech

final class ShortcutPassthroughTests: XCTestCase {
    // The saved Fn+Command toggle can have either modifier as its primary
    // key, depending on which one was pressed first in the recorder.
    private func fnCommandToggle(primary: UInt16) -> ShortcutBinding {
        ShortcutBinding(
            keyCode: primary,
            keyDisplay: ShortcutKeyNames.name(forKeyCode: primary),
            modifiers: primary == 63 ? .command : .function,
            kind: .modifierKey,
            preset: nil,
            exactModifierKeyCodes: [55, 63]
        )
    }

    func testCommandTabPassesThroughWithRecordedFnCommandToggle() {
        for primary: UInt16 in [55, 63] {
            var matcher = ShortcutMatcher(configuration: .init(
                hold: ShortcutPreset.fnKey.binding,
                toggle: fnCommandToggle(primary: primary)
            ))
            let events: [ShortcutMatcher.InputEvent] = [
                .modifierChanged(keyCode: 55, isDown: true),
                .keyChanged(keyCode: 48, isDown: true),
                .keyChanged(keyCode: 48, isDown: false),
                .keyChanged(keyCode: 48, isDown: true),
                .keyChanged(keyCode: 48, isDown: false),
                .modifierChanged(keyCode: 55, isDown: false)
            ]
            for event in events {
                XCTAssertEqual(matcher.handle(event), .passthrough, "System must receive \(event); primary=\(primary)")
            }
            XCTAssertEqual(matcher.drainEvents(), [])
        }
    }

    func testReverseAppSwitchingAndOrdinaryCommandShortcutsPassThrough() {
        var matcher = ShortcutMatcher(configuration: .init(hold: .disabled, toggle: fnCommandToggle(primary: 55)))
        let events: [ShortcutMatcher.InputEvent] = [
            .modifierChanged(keyCode: 55, isDown: true),
            .modifierChanged(keyCode: 56, isDown: true),
            .keyChanged(keyCode: 48, isDown: true),
            .keyChanged(keyCode: 48, isDown: false),
            .modifierChanged(keyCode: 56, isDown: false),
            .keyChanged(keyCode: 8, isDown: true), // Command-C
            .keyChanged(keyCode: 8, isDown: false),
            .keyChanged(keyCode: 49, isDown: true), // Command-Space
            .keyChanged(keyCode: 49, isDown: false),
            .modifierChanged(keyCode: 55, isDown: false)
        ]
        for event in events { XCTAssertEqual(matcher.handle(event), .passthrough, "\(event)") }
        XCTAssertEqual(matcher.drainEvents(), [])
    }

    func testAppSwitchingModifiersPassThroughWhileHoldingDictationKey() {
        for hold in [ShortcutPreset.f5.binding, ShortcutPreset.rightOption.binding] {
            var matcher = ShortcutMatcher(configuration: .init(hold: hold, toggle: .disabled))
            let down: ShortcutMatcher.InputEvent = hold.kind == .key
                ? .keyChanged(keyCode: hold.keyCode, isDown: true)
                : .modifierChanged(keyCode: hold.keyCode, isDown: true)
            let up: ShortcutMatcher.InputEvent = hold.kind == .key
                ? .keyChanged(keyCode: hold.keyCode, isDown: false)
                : .modifierChanged(keyCode: hold.keyCode, isDown: false)
            XCTAssertEqual(matcher.handle(down), .consume)
            XCTAssertEqual(matcher.drainEvents(), [.holdActivated])
            for event: ShortcutMatcher.InputEvent in [
                .modifierChanged(keyCode: 55, isDown: true),
                .keyChanged(keyCode: 48, isDown: true),
                .keyChanged(keyCode: 48, isDown: false),
                .modifierChanged(keyCode: 55, isDown: false)
            ] {
                XCTAssertEqual(matcher.handle(event), .passthrough, "Unrelated app-switching event: \(event)")
            }
            XCTAssertEqual(matcher.drainEvents(), [])
            XCTAssertEqual(matcher.handle(up), .consume)
            XCTAssertEqual(matcher.drainEvents(), [.holdDeactivated])
        }
    }

    func testFnCommandToggleStillFiresInEitherPressOrder() {
        for primary: UInt16 in [55, 63] {
            for order: [UInt16] in [[55, 63], [63, 55]] {
                var matcher = ShortcutMatcher(configuration: .init(hold: .disabled, toggle: fnCommandToggle(primary: primary)))
                let firstDecision = matcher.handle(.modifierChanged(keyCode: order[0], isDown: true))
                XCTAssertEqual(firstDecision, order[0] == 63 ? .consume : .passthrough)
                XCTAssertEqual(matcher.drainEvents(), [])
                XCTAssertEqual(matcher.handle(.modifierChanged(keyCode: order[1], isDown: true)), .consume)
                XCTAssertEqual(matcher.drainEvents(), [.toggleActivated])
                XCTAssertEqual(matcher.handle(.modifierChanged(keyCode: order[1], isDown: false)), .consume)
                XCTAssertEqual(matcher.drainEvents(), [.toggleDeactivated])
                XCTAssertEqual(matcher.handle(.modifierChanged(keyCode: order[0], isDown: false)), firstDecision)
            }
        }
    }

    func testStandaloneModifierBindingStillConsumesItsOwnKey() {
        let command = ShortcutBinding(
            keyCode: 55, keyDisplay: "Command", modifiers: [],
            kind: .modifierKey, preset: nil, exactModifierKeyCodes: [55]
        )
        var matcher = ShortcutMatcher(configuration: .init(hold: .disabled, toggle: command))
        XCTAssertEqual(matcher.handle(.modifierChanged(keyCode: 55, isDown: true)), .consume)
        XCTAssertEqual(matcher.drainEvents(), [.toggleActivated])
        XCTAssertEqual(matcher.handle(.modifierChanged(keyCode: 55, isDown: false)), .consume)
        XCTAssertEqual(matcher.drainEvents(), [.toggleDeactivated])
    }
}
