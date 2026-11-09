import XCTest
@testable import QuietSpeech

final class ShortcutCaptureTests: XCTestCase {
    func testEachStandaloneModifierSurvivesReleaseAndActivatesAfterSaving() throws {
        for keyCode in ShortcutBinding.modifierKeyCodes.sorted() {
            var capture = ShortcutCaptureState()
            XCTAssertNil(capture.modifierChanged(keyCode: keyCode, isDown: true))
            let binding = try XCTUnwrap(capture.modifierChanged(keyCode: keyCode, isDown: false))
            XCTAssertEqual(binding.keyCode, keyCode)
            XCTAssertEqual(binding.kind, .modifierKey)
            XCTAssertEqual(binding.exactModifierKeyCodes, [keyCode])
            XCTAssertEqual(binding.modifiers, [])
            try assertHoldActivatesAfterSaving(binding, modifiers: [keyCode])
        }
    }

    func testModifierChordSurvivesEitherReleaseOrder() throws {
        for releaseOrder: [UInt16] in [[63, 55], [55, 63]] {
            var capture = ShortcutCaptureState()
            XCTAssertNil(capture.modifierChanged(keyCode: 63, isDown: true))
            XCTAssertNil(capture.modifierChanged(keyCode: 55, isDown: true))
            XCTAssertNil(capture.modifierChanged(keyCode: releaseOrder[0], isDown: false))
            let binding = try XCTUnwrap(capture.modifierChanged(keyCode: releaseOrder[1], isDown: false))
            XCTAssertEqual(binding.keyCode, 63)
            XCTAssertEqual(binding.modifiers, .command)
            XCTAssertEqual(binding.exactModifierKeyCodes, [63, 55])
            try assertHoldActivatesAfterSaving(binding, modifiers: [63, 55])
        }
    }

    func testKeyCombinationKeepsModifierSideAndReplacesOldBinding() throws {
        var capture = ShortcutCaptureState()
        XCTAssertNil(capture.modifierChanged(keyCode: 61, isDown: true))
        let binding = try XCTUnwrap(capture.keyBinding(for: 49))
        XCTAssertEqual(binding.modifiers, .option)
        XCTAssertEqual(binding.exactModifierKeyCodes, [61])
        try assertHoldActivatesAfterSaving(binding, modifiers: [61])

        var matcher = ShortcutMatcher()
        matcher.update(configuration: .init(hold: binding, toggle: .disabled))
        _ = matcher.handle(.modifierChanged(keyCode: 63, isDown: true))
        _ = matcher.handle(.modifierChanged(keyCode: 63, isDown: false))
        _ = matcher.handle(.modifierChanged(keyCode: 58, isDown: true))
        _ = matcher.handle(.keyChanged(keyCode: 49, isDown: true))
        XCTAssertEqual(matcher.drainEvents(), [], "Fn and left Option must not trigger the new right Option binding")
    }

    func testFunctionKeysCanBeRecordedWithoutModifiers() throws {
        let capture = ShortcutCaptureState()
        let keyCodes: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
                                  103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
        for (index, keyCode) in keyCodes.enumerated() {
            let binding = try XCTUnwrap(capture.keyBinding(for: keyCode))
            XCTAssertEqual(binding.displayName, "F\(index + 1)")
            try assertHoldActivatesAfterSaving(binding, modifiers: [])
        }
        XCTAssertNil(capture.keyBinding(for: 0), "Bare A must not intercept normal typing")
        XCTAssertNil(capture.keyBinding(for: 102), "JIS Eisu is not a function key")
    }

    func testCancelledCaptureAndUnmatchedReleaseDoNotCreateBindings() throws {
        var capture = ShortcutCaptureState()
        XCTAssertNil(capture.modifierChanged(keyCode: 61, isDown: false))
        XCTAssertNil(capture.modifierChanged(keyCode: 61, isDown: true))
        capture.reset()
        XCTAssertNil(capture.modifierChanged(keyCode: 61, isDown: false))
        XCTAssertNil(capture.modifierChanged(keyCode: 55, isDown: true))
        let binding = try XCTUnwrap(capture.modifierChanged(keyCode: 55, isDown: false))
        XCTAssertEqual(binding.keyCode, 55)
        XCTAssertEqual(binding.exactModifierKeyCodes, [55])
    }

    func testRecordedModifierWorksForToggleAndPasteAgain() throws {
        var capture = ShortcutCaptureState()
        _ = capture.modifierChanged(keyCode: 61, isDown: true)
        let binding = try XCTUnwrap(capture.modifierChanged(keyCode: 61, isDown: false))
        var toggle = ShortcutMatcher(configuration: .init(hold: .disabled, toggle: binding))
        XCTAssertEqual(toggle.handle(.modifierChanged(keyCode: 61, isDown: true)), .consume)
        XCTAssertEqual(toggle.drainEvents(), [.toggleActivated])
        XCTAssertEqual(toggle.handle(.modifierChanged(keyCode: 61, isDown: false)), .consume)
        XCTAssertEqual(toggle.drainEvents(), [.toggleDeactivated])

        var paste = ShortcutMatcher(configuration: .init(hold: .disabled, toggle: .disabled, copyAgain: binding))
        _ = paste.handle(.modifierChanged(keyCode: 61, isDown: true))
        _ = paste.handle(.modifierChanged(keyCode: 61, isDown: false))
        XCTAssertEqual(paste.drainEvents(), [.copyAgainTriggered])
    }

    private func assertHoldActivatesAfterSaving(
        _ binding: ShortcutBinding,
        modifiers: [UInt16],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let configuration = ShortcutConfiguration(hold: binding, toggle: .disabled)
        let saved = try JSONEncoder().encode(configuration)
        var matcher = ShortcutMatcher(configuration: try JSONDecoder().decode(ShortcutConfiguration.self, from: saved))
        for keyCode in modifiers {
            _ = matcher.handle(.modifierChanged(keyCode: keyCode, isDown: true))
        }
        if binding.kind == .key {
            XCTAssertEqual(matcher.handle(.keyChanged(keyCode: binding.keyCode, isDown: true)), .consume, file: file, line: line)
        }
        XCTAssertEqual(matcher.drainEvents(), [.holdActivated], file: file, line: line)
        if binding.kind == .key {
            XCTAssertEqual(matcher.handle(.keyChanged(keyCode: binding.keyCode, isDown: false)), .consume, file: file, line: line)
        }
        for keyCode in modifiers.reversed() {
            _ = matcher.handle(.modifierChanged(keyCode: keyCode, isDown: false))
        }
        XCTAssertEqual(matcher.drainEvents(), [.holdDeactivated], file: file, line: line)
    }
}
