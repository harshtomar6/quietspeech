import SwiftUI
import AppKit

/// Click, then press a key combination to rebind. A single modifier key (Fn,
/// Right Option, …) can be bound on its own by pressing and releasing it; a
/// modifier plus a key binds that combination, remembering which side each
/// modifier was on. Esc cancels, Delete clears.
struct ShortcutRecorder: View {
    @Binding var binding: ShortcutBinding
    var onCaptureStateChanged: (Bool) -> Void = { _ in }
    var onCapture: () -> Void

    @State private var isRecording = false
    @State private var pressedModifierKeyCodes: [UInt16] = []
    @State private var needsModifier = false
    @State private var monitors: [Any] = []

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(isRecording ? (needsModifier ? "Add a modifier…" : "Press keys…") : binding.displayName)
                    .frame(minWidth: 140)
            }

            if !binding.isDisabled {
                Button {
                    commit(.disabled)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear this shortcut")
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        guard !isRecording else { return }
        isRecording = true
        needsModifier = false
        pressedModifierKeyCodes = []
        onCaptureStateChanged(true)

        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged],
            handler: { event in handleFlagsChanged(event) }
        ) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown],
            handler: { event in handleKeyDown(event) }
        ) {
            monitors.append(monitor)
        }
    }

    private func stop() {
        guard isRecording else { return }
        isRecording = false
        needsModifier = false
        pressedModifierKeyCodes = []
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        onCaptureStateChanged(false)
    }

    private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {
        let keyCode = event.keyCode
        guard ModifierKeyEventState.isModifierKeyCode(keyCode) else { return nil }

        let flag = ModifierKeyEventState.mappedFlag(for: keyCode) ?? .maskSecondaryFn
        let isDown = UInt64(event.modifierFlags.rawValue) & flag.rawValue != 0
        if isDown {
            if !pressedModifierKeyCodes.contains(keyCode) {
                pressedModifierKeyCodes.append(keyCode)
            }
        } else {
            pressedModifierKeyCodes.removeAll { $0 == keyCode }
            // All modifiers released without a key in between: bind the
            // modifier itself (or the modifier chord) on its own.
            if pressedModifierKeyCodes.isEmpty {
                commit(modifierOnlyBinding())
            }
        }
        return nil
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 { stop(); return nil }                          // Esc cancels
        if event.keyCode == 51 || event.keyCode == 117 {                        // Delete clears
            commit(.disabled)
            return nil
        }

        let modifiers = logicalModifiers(for: pressedModifierKeyCodes)
        // A bare letter would swallow typing everywhere, so a no-modifier
        // binding is only allowed for function keys.
        guard !modifiers.isEmpty || Self.isFunctionKey(event.keyCode) else {
            needsModifier = true
            return nil
        }

        commit(ShortcutBinding(
            keyCode: event.keyCode,
            keyDisplay: ShortcutKeyNames.name(forKeyCode: event.keyCode),
            modifiers: modifiers,
            kind: .key,
            preset: nil,
            exactModifierKeyCodes: pressedModifierKeyCodes.isEmpty ? nil : Set(pressedModifierKeyCodes)
        ))
        return nil
    }

    /// The first modifier pressed is the key; any others become its modifiers.
    /// Fn then Cmd therefore reads as "Fn with Cmd", matching the default
    /// latch so the recorded binding displays the way it behaves.
    private func modifierOnlyBinding() -> ShortcutBinding {
        let primary = pressedModifierKeyCodes.first ?? ShortcutPreset.fnKey.binding.keyCode
        let others = pressedModifierKeyCodes.dropFirst()
        return ShortcutBinding(
            keyCode: primary,
            keyDisplay: ShortcutKeyNames.name(forKeyCode: primary),
            modifiers: logicalModifiers(for: Array(others)),
            kind: .modifierKey,
            preset: ShortcutPreset.matching(keyCode: primary),
            exactModifierKeyCodes: Set(pressedModifierKeyCodes)
        )
    }

    private func logicalModifiers(for keyCodes: [UInt16]) -> ShortcutModifiers {
        ShortcutBinding.modifiers(for: Set(keyCodes))
    }

    private func commit(_ newBinding: ShortcutBinding) {
        stop()
        binding = newBinding
        onCapture()
    }

    private static func isFunctionKey(_ keyCode: UInt16) -> Bool {
        (96...111).contains(Int(keyCode))
    }
}
