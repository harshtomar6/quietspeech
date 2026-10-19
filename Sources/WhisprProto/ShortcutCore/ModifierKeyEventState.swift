import AppKit

// Derived from FreeFlow (https://github.com/zachlatta/freeflow),
// Sources/ModifierKeyEventState.swift, Copyright (c) Zach Latta, MIT licensed.
//
// Fn is tracked by keyCode rather than by flag: `maskSecondaryFn` is also set
// by arrow keys and some media keys, so trusting the flag makes Fn appear
// pressed when it is not (the "arrow key looks like Fn" bug).

struct ModifierKeyEventState: Equatable {
    static let fnKeyCode: UInt16 = 63

    private(set) var pressedModifierKeyCodes: Set<UInt16> = []

    static func mappedFlag(for keyCode: UInt16) -> CGEventFlags? {
        switch keyCode {
        case 54, 55: return .maskCommand
        case 56, 60: return .maskShift
        case 58, 61: return .maskAlternate
        case 59, 62: return .maskControl
        case fnKeyCode: return .maskSecondaryFn
        default: return nil
        }
    }

    static func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        ShortcutBinding.modifierKeyCodes.contains(keyCode)
    }

    /// The Fn bit as the system currently reports it. Used only to seed state
    /// after a tap restart, never as the source of truth for a binding.
    static func currentFunctionKeyIsDown() -> Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn)
    }

    mutating func markDown(_ keyCode: UInt16) {
        guard Self.isModifierKeyCode(keyCode) else { return }
        pressedModifierKeyCodes.insert(keyCode)
    }

    mutating func markUp(_ keyCode: UInt16) {
        pressedModifierKeyCodes.remove(keyCode)
    }

    mutating func replace(with keyCodes: Set<UInt16>) {
        pressedModifierKeyCodes = keyCodes
    }

    mutating func reset() {
        pressedModifierKeyCodes.removeAll()
    }

    /// Key codes for a logical modifier set, crediting Fn only when the system
    /// says Fn itself is down.
    func pressedModifierKeyCodes(
        for modifiers: ShortcutModifiers,
        trustedFunctionKeyIsDown: Bool
    ) -> Set<UInt16> {
        var result = pressedModifierKeyCodes
        if !trustedFunctionKeyIsDown {
            result.remove(Self.fnKeyCode)
        }
        if result.isEmpty { return [] }
        return result
    }
}
