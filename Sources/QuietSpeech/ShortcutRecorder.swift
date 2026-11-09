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
    @State private var captureState = ShortcutCaptureState()
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
        captureState.reset()
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
        captureState.reset()
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        onCaptureStateChanged(false)
    }

    private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {
        let keyCode = event.keyCode
        guard ModifierKeyEventState.isModifierKeyCode(keyCode) else { return nil }

        let flag = ModifierKeyEventState.mappedFlag(for: keyCode) ?? .maskSecondaryFn
        let isDown = UInt64(event.modifierFlags.rawValue) & flag.rawValue != 0
        if let binding = captureState.modifierChanged(keyCode: keyCode, isDown: isDown) {
            commit(binding)
        }
        return nil
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 { stop(); return nil }                          // Esc cancels
        if event.keyCode == 51 || event.keyCode == 117 {                        // Delete clears
            commit(.disabled)
            return nil
        }

        guard let binding = captureState.keyBinding(for: event.keyCode) else {
            needsModifier = true
            return nil
        }

        commit(binding)
        return nil
    }

    private func commit(_ newBinding: ShortcutBinding) {
        stop()
        binding = newBinding
        onCapture()
    }
}
