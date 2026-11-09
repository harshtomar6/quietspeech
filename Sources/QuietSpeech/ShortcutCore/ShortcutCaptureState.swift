import Foundation

/// Keeps the recorded chord separate from the keys still held during release.
struct ShortcutCaptureState {
    private var pressedModifierKeyCodes: [UInt16] = []
    private var recordedModifierKeyCodes: [UInt16] = []

    mutating func reset() {
        pressedModifierKeyCodes = []
        recordedModifierKeyCodes = []
    }

    mutating func modifierChanged(keyCode: UInt16, isDown: Bool) -> ShortcutBinding? {
        guard ShortcutBinding.modifierKeyCodes.contains(keyCode) else { return nil }
        if isDown {
            if !pressedModifierKeyCodes.contains(keyCode) {
                pressedModifierKeyCodes.append(keyCode)
                recordedModifierKeyCodes = pressedModifierKeyCodes
            }
            return nil
        }

        guard pressedModifierKeyCodes.contains(keyCode) else { return nil }
        pressedModifierKeyCodes.removeAll { $0 == keyCode }
        guard pressedModifierKeyCodes.isEmpty,
              let primary = recordedModifierKeyCodes.first else { return nil }

        let binding = ShortcutBinding(
            keyCode: primary,
            keyDisplay: ShortcutKeyNames.name(forKeyCode: primary),
            modifiers: ShortcutBinding.modifiers(for: Set(recordedModifierKeyCodes.dropFirst())),
            kind: .modifierKey,
            preset: ShortcutPreset.matching(keyCode: primary),
            exactModifierKeyCodes: Set(recordedModifierKeyCodes)
        )
        reset()
        return binding
    }

    func keyBinding(for keyCode: UInt16) -> ShortcutBinding? {
        let modifiers = ShortcutBinding.modifiers(for: Set(pressedModifierKeyCodes))
        // Bare letters would swallow ordinary typing everywhere.
        guard !modifiers.isEmpty || Self.functionKeyCodes.contains(keyCode) else { return nil }
        return ShortcutBinding(
            keyCode: keyCode,
            keyDisplay: ShortcutKeyNames.name(forKeyCode: keyCode),
            modifiers: modifiers,
            kind: .key,
            preset: nil,
            exactModifierKeyCodes: pressedModifierKeyCodes.isEmpty ? nil : Set(pressedModifierKeyCodes)
        )
    }

    // macOS virtual key codes for F1–F20 are not a contiguous range.
    private static let functionKeyCodes: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
        103, 111, 105, 107, 113, 106, 64, 79, 80, 90
    ]
}
