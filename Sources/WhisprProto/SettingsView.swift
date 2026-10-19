import SwiftUI
import AppKit

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    activationSection
                    transcriptionSection
                    outputSection
                    overlaySection
                    captureSection
                    permissionsSection
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 22)
            }
        }
        .frame(width: 620, height: 740)
        .onAppear { model.refreshPermissions() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            IconTile(symbol: "waveform", size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("Whispr Proto")
                    .font(.system(size: 16, weight: .semibold))
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !model.microphoneGranted || !model.accessibilityGranted {
                Label("Setup needed", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.orange.opacity(0.14)))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var statusLine: String {
        "\(model.shortcutConfiguration.summary) \u{00b7} \(model.overlayStyle.label) overlay \u{00b7} on-device"
    }

    // MARK: - Sections

    private var activationSection: some View {
        section("Activation", symbol: "command", note: activationNote) {
            bindingRow(.hold)
            RowDivider()
            bindingRow(.toggle)
            RowDivider()
            bindingRow(.copyAgain)
        }
    }

    private func bindingRow(_ role: ShortcutRole) -> some View {
        SettingRow(role.title, subtitle: role.detail) {
            ShortcutRecorder(
                binding: Binding(
                    get: { model.shortcutConfiguration.binding(for: role) },
                    set: { model.setBinding($0, for: role) }
                ),
                onCaptureStateChanged: { model.setShortcutCapture($0) },
                onCapture: {
                    model.applyActivation()
                    model.refreshPermissions()
                }
            )        }
    }

    private var activationNote: String {
        if !model.shortcutConfiguration.conflictingRoles.isEmpty {
            return "Those shortcuts overlap, so both would fire at once. Change one of them."
        }
        if model.shortcutConfiguration.hold.usesFnKey || model.shortcutConfiguration.toggle.usesFnKey {
            return "Hold Fn to talk, or add ⌘ while holding to latch into tap mode without interrupting the recording. If Fn opens the emoji picker, set “Press 🌐 key to” to “Do nothing” in System Settings › Keyboard."
        }
        return "Speak while the keys are held, or press once to start and again to stop. Both need Accessibility."
    }

    private var transcriptionSection: some View {
        section("Transcription", symbol: "waveform",
                note: "Cleanup rewrites filler, spoken punctuation and self-corrections with fixed rules, so it can never add words you didn't say.") {
            SettingRow("Language") {
                Picker("", selection: $model.language) {
                    ForEach(AppModel.Language.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 170)
                .onChange(of: model.language) { _, _ in model.persistPreferences() }
            }

            RowDivider()

            SettingRow("Cleanup") {
                Picker("", selection: $model.cleanMode) {
                    ForEach(AppModel.CleanMode.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 170)
                .onChange(of: model.cleanMode) { _, _ in
                    model.persistPreferences()
                    model.refreshCleaned()
                }
            }
        }
    }

    private var outputSection: some View {
        section("Output", symbol: "text.cursor", note: insertionNote) {
            SettingRow("Type the result into the frontmost app") {
                Toggle("", isOn: $model.autoInsert)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: model.autoInsert) { _, _ in model.persistPreferences() }
            }

            RowDivider()

            SettingRow("Insert at the cursor without using the clipboard") {
                Toggle("", isOn: $model.useDirectInsertion)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: model.useDirectInsertion) { _, _ in model.persistPreferences() }
            }
        }
    }

    private var overlaySection: some View {
        section("Overlay", symbol: "rectangle.on.rectangle", note: model.overlayStyle.detail) {
            SettingRow("Style") {
                Picker("", selection: $model.overlayStyle) {
                    ForEach(AppModel.OverlayStyle.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 190)
                .onChange(of: model.overlayStyle) { _, _ in
                    model.persistPreferences()
                    model.previewOverlay()
                }
            }

            RowDivider()

            SettingRow("Preview", subtitle: "See it without dictating") {
                Button("Show overlay") { model.previewOverlay() }
                    .controlSize(.small)
            }
        }
    }

    private var captureSection: some View {
        section("Reviewing cleanup", symbol: "checklist",
                note: "Off by default. When on, every finished dictation is appended to a file on this Mac only — nothing is sent anywhere — so you can compare what you said with what was cleaned up.") {
            SettingRow("Save each dictation (raw and cleaned)") {
                Toggle("", isOn: $model.captureDictations)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: model.captureDictations) { _, _ in
                        model.persistPreferences()
                        model.refreshCaptureStatus()
                    }
            }

            RowDivider()

            SettingRow("Capture file", subtitle: model.captureStatus) {
                HStack(spacing: 8) {
                    Button("Reveal") { model.revealCaptureFile() }
                        .controlSize(.small)
                    Button("Delete") { model.clearCaptureFile() }
                        .controlSize(.small)
                }
            }
        }
    }

    private var permissionsSection: some View {
        section("Permissions", symbol: "lock.shield",
                note: "macOS re-reads permissions per process, so relaunch the app after granting.") {
            permissionRow("Microphone", granted: model.microphoneGranted) {
                Task { _ = await Permissions.requestMicrophone(); model.refreshPermissions() }
            }

            RowDivider()

            permissionRow("Accessibility", granted: model.accessibilityGranted) {
                model.requestAccessibility()
            }

            RowDivider()

            HStack(spacing: 8) {
                Text("Changed something in System Settings?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Recheck") { model.refreshPermissions() }
                    .controlSize(.small)
                Button("Relaunch") { model.relaunch() }
                    .controlSize(.small)
            }
            .padding(.vertical, 11)
        }
    }

    // MARK: - Pieces

    private func section<Content: View>(_ title: String, symbol: String, note: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.7)
            }
            .foregroundStyle(.secondary)
            .padding(.leading, 3)

            SectionCard { content() }

            if let note { SettingNote(note) }
        }
    }

    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 15))
                .foregroundStyle(granted ? Color.green : Color.orange)

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                Text(granted ? "Granted" : "Needs permission")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if !granted {
                Button("Grant", action: action)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 11)
    }

    private var insertionNote: String {
        model.useDirectInsertion
            ? "Never uses the clipboard. Tries an Accessibility write, then synthetic typing, and only pastes if both fail — so clipboard managers like FlyCut never record your dictations."
            : "Always pastes via the clipboard and a synthesized ⌘V; your previous clipboard is restored. Note: clipboard managers that ignore the nspasteboard.org markers (e.g. FlyCut 1.9.6) will record every dictation."
    }
}

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
