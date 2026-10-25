import SwiftUI
import AppKit

// MARK: - Overview

struct OverviewPane: View {
    @Bindable var model: AppModel
    var navigate: (SettingsPane) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsPaneHeader(
                title: "Overview",
                subtitle: "Choose how QuietSpeech listens, cleans up, and types.",
                pill: SettingsStatusPill(text: statusText, tone: statusTone)
            )
            .padding(.bottom, 2)

            SettingsGroup("Dictation", icon: "waveform") {
                navRow(
                    title: "Activation",
                    detail: activationDetail,
                    pane: .activation
                ) {
                    activationKeys
                }

                SettingsDivider()

                SettingsRow(
                    "Intelligence",
                    subtitle: intelligenceDetail
                ) {
                    SettingsToggle(isOn: $model.aiPolishEnabled) { _ in
                        model.persistPreferences()
                    }
                }

                SettingsDivider()

                SettingsRow(
                    "Overlay",
                    subtitle: "Shown while you dictate"
                ) {
                    Picker("", selection: $model.overlayStyle) {
                        ForEach(AppModel.OverlayStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                    .onChange(of: model.overlayStyle) { _, _ in
                        model.persistPreferences()
                    }
                }
            }

            SettingsGroup("Setup", icon: "checkmark.seal") {
                setupRow(
                    title: "Microphone",
                    detail: "Listening on demand",
                    status: model.microphoneGranted ? "Granted" : "Needed",
                    tone: model.microphoneGranted ? .green : .amber,
                    pane: .permissions
                )
                SettingsDivider()
                setupRow(
                    title: "Accessibility",
                    detail: "Shortcuts and typing",
                    status: model.accessibilityGranted ? "Enabled" : "Needed",
                    tone: model.accessibilityGranted ? .green : .amber,
                    pane: .permissions
                )
                SettingsDivider()
                setupRow(
                    title: "AI provider",
                    detail: aiSetupDetail,
                    status: aiSetupStatus,
                    tone: aiSetupTone,
                    pane: .ai
                )
                SettingsDivider()
                setupRow(
                    title: "License",
                    detail: model.license.overviewDetail,
                    status: model.license.overviewStatus,
                    tone: licenseTone,
                    pane: .license
                )
                SettingsDivider()
                setupRow(
                    title: "Local history",
                    detail: localHistoryDetail,
                    status: model.historyEnabled ? "On this Mac" : "Paused",
                    tone: model.historyEnabled ? .neutral : .amber,
                    pane: .history
                )
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Recent dictations")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Show All") { navigate(.history) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SettingsColor.accent)
                }
                .padding(.horizontal, 2)

                SettingsCard {
                    if model.history.isEmpty {
                        SettingsEmptyState(
                            icon: "waveform",
                            title: "No dictations yet",
                            message: "Your next dictation will show up here."
                        )
                    } else {
                        ForEach(Array(model.history.prefix(2).enumerated()), id: \.element.id) { index, record in
                            recentRow(record)
                            if index < min(model.history.count, 2) - 1 {
                                SettingsDivider()
                            }
                        }
                    }
                }
            }

            SettingsNote(privacyNote, icon: "lock")
                .padding(.top, 2)
        }
    }

    // MARK: Rows

    private func navRow<Trailing: View>(
        title: String,
        detail: String,
        pane: SettingsPane,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        Button {
            navigate(pane)
        } label: {
            HStack(spacing: 11) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 10)
                trailing()
                chevron
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityHint("Opens \(pane.label) settings")
    }

    private func setupRow(
        title: String,
        detail: String,
        status: String,
        tone: SettingsStatusPill.Tone,
        pane: SettingsPane
    ) -> some View {
        Button {
            navigate(pane)
        } label: {
            HStack(spacing: 11) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 10)
                SettingsStatusPill(text: status, tone: tone)
                chevron
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(status)")
        .accessibilityHint("Opens \(pane.label) settings")
    }

    private func recentRow(_ record: DictationRecord) -> some View {
        Button {
            navigate(.history)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.text)
                        .font(.system(size: 13, weight: .regular))
                        .lineLimit(1)
                    Text("\(record.appName) \u{00b7} \(relative(record.date))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.tertiary)
    }

    private var activationKeys: some View {
        HStack(spacing: 8) {
            if model.shortcutConfiguration.hold.isDisabled,
               model.shortcutConfiguration.toggle.isDisabled {
                Text("Off")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                if !model.shortcutConfiguration.hold.isDisabled {
                    keycaps(model.shortcutConfiguration.hold.displayName)
                }
                if !model.shortcutConfiguration.toggle.isDisabled {
                    keycaps(model.shortcutConfiguration.toggle.displayName)
                }
            }
        }
    }

    private func keycaps(_ display: String) -> some View {
        let parts = display.components(separatedBy: " + ")
        return HStack(spacing: 3) {
            ForEach(parts.indices, id: \.self) { index in
                if index > 0 {
                    Text("+")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                Text(parts[index])
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 5)
                    .frame(height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(SettingsColor.cardMuted)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(SettingsColor.borderStrong, lineWidth: 1)
                    )
            }
        }
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: Copy

    private var aiSetupDetail: String {
        if model.aiProvider == .apple {
            return model.appleIntelligenceAvailable
                ? "Apple Intelligence on this Mac"
                : "Unavailable — choose another provider"
        }
        if model.aiKeyConfigured { return "\(model.settingsProviderName) connected with your key" }
        if model.aiConfigured { return "Local endpoint, no key needed" }
        return "Choose a provider in AI"
    }

    private var aiSetupStatus: String {
        if model.aiProvider == .apple, !model.appleIntelligenceAvailable { return "Unavailable" }
        return model.aiConfigured ? "Ready" : "Optional"
    }

    private var aiSetupTone: SettingsStatusPill.Tone {
        if model.aiProvider == .apple, !model.appleIntelligenceAvailable { return .amber }
        return model.aiConfigured ? .green : .neutral
    }

    private var licenseTone: SettingsStatusPill.Tone {
        switch model.license.statusTone {
        case .green: return .green
        case .amber: return .amber
        case .accent: return .accent
        case .neutral: return .neutral
        }
    }

    private var localHistoryDetail: String {
        if !model.historyEnabled { return "History is paused" }
        return model.history.isEmpty ? "No dictations saved yet" : "Recent dictations saved on this Mac"
    }

    private var intelligenceDetail: String {
        guard model.aiConfigured else { return "On-device cleanup only" }
        var parts = [model.settingsProviderName]
        if model.aiProvider != .apple { parts.append(model.aiModel) }
        if model.providerTranscriptionActive { parts.append("Provider audio") }
        if model.aiPolishEnabled { parts.append("Polish on") }
        if model.aiEnabled { parts.append("Edit on") }
        if model.aiGenerateEnabled { parts.append("Generate on") }
        return parts.joined(separator: " \u{00b7} ")
    }

    private var privacyNote: String {
        if model.providerTranscriptionActive {
            return "Audio reaches \(model.settingsProviderName) for transcription. Text reaches it only when an AI feature runs."
        }
        if model.aiProvider == .apple {
            return "Audio stays on this Mac. Apple Intelligence processes text on-device when AI is on."
        }
        if model.aiReady, model.aiConfigured {
            return "Audio stays on this Mac. Text reaches \(model.settingsProviderName) only when AI is on."
        }
        return "Audio stays on this Mac. AI is off, so nothing leaves your Mac."
    }

    // MARK: Status

    private var statusText: String {
        if !model.settingsSetupComplete { return "Setup needed" }
        return model.aiReady ? "Ready" : "On-device"
    }

    private var statusTone: SettingsStatusPill.Tone {
        if !model.settingsSetupComplete { return .amber }
        return model.aiReady ? .green : .accent
    }

    private var activationDetail: String {
        let hold = model.shortcutConfiguration.hold
        let toggle = model.shortcutConfiguration.toggle
        if hold.isDisabled && toggle.isDisabled { return "No shortcut set" }
        if hold.isDisabled { return "Tap \(toggle.displayName) to toggle" }
        if toggle.isDisabled { return "Hold \(hold.displayName) to talk" }
        return "Hold \(hold.displayName) to talk, or tap \(toggle.displayName) to toggle"
    }
}

// MARK: - Activation

struct ActivationPane: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            SettingsPaneHeader(
                title: "Activation",
                subtitle: "Choose the keys that start and stop dictation."
            )

            SettingsGroup("Shortcuts", icon: "command", note: activationNote) {
                shortcutRow(.hold)
                SettingsDivider()
                shortcutRow(.toggle)
                SettingsDivider()
                shortcutRow(.copyAgain)
            }

            SettingsGroup("Fn key", icon: "key") {
                SettingsRow(
                    "Emoji picker takes over Fn",
                    subtitle: "If pressing Fn opens the emoji picker, set “Press globe key to” to “Do nothing” in System Settings › Keyboard."
                ) {
                    Button("Open Keyboard") { openKeyboardSettings() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }

    private func shortcutRow(_ role: ShortcutRole) -> some View {
        SettingsRow(role.title, subtitle: role.detail) {
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
            )
        }
    }

    private var activationNote: String {
        if !model.shortcutConfiguration.conflictingRoles.isEmpty {
            return "Those shortcuts overlap, so both would fire at once. Change one of them."
        }
        return "Click a shortcut, then press the keys you want. Esc cancels, Delete clears. Fn works as a standalone key."
    }

    private func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Transcription

struct TranscriptionPane: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            SettingsPaneHeader(
                title: "Transcription",
                subtitle: "Language, cleanup, and how text adapts to the app you’re in."
            )

            SettingsGroup(
                "Recognition",
                icon: "waveform",
                note: "Cleanup rewrites filler, spoken punctuation and self-corrections with fixed rules, so it can never add words you didn’t say. Say “new paragraph”, “new line” or “bullet point” to lay text out."
            ) {
                SettingsRow("Language", subtitle: "Used by dictation and by provider transcription.") {
                    Picker("", selection: $model.language) {
                        ForEach(AppModel.Language.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 185)
                    .onChange(of: model.language) { _, _ in model.persistPreferences() }
                }

                SettingsDivider()

                SettingsRow("Cleanup", subtitle: "Fixed rules rewrite filler and self-corrections.") {
                    SettingsSegmentedControl(
                        options: AppModel.CleanMode.allCases.map { ($0, $0.label) },
                        selection: $model.cleanMode
                    )
                    .frame(width: 215)
                    .onChange(of: model.cleanMode) { _, _ in
                        model.persistPreferences()
                        model.refreshCleaned()
                    }
                }
            }

            SettingsGroup(
                "Context",
                icon: "app.badge",
                note: "Code and Terminal skip capitalization and the final period, and accept spoken symbols like “open brace”, “pipe”, or “double equals”. Detection happens locally when dictation starts."
            ) {
                SettingsRow("Mode", subtitle: "Auto looks at the frontmost app, and the tab title in browsers.") {
                    Picker("", selection: $model.contextMode) {
                        ForEach(ContextMode.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 185)
                    .onChange(of: model.contextMode) { _, _ in model.contextModeChanged() }
                }

                SettingsDivider()

                SettingsRow("Right now", subtitle: "Detected from the last frontmost app.") {
                    contextPill
                }
            }
        }
    }

    private var contextPill: some View {
        let detected = model.hasContext
        let appName = model.targetApp?.localizedName
        let text: String
        if let appName, detected {
            text = "\(appName) \u{00b7} \(model.activeProfile.label)"
        } else if detected {
            text = model.activeProfile.label
        } else {
            text = "Waiting for dictation"
        }
        return SettingsStatusPill(text: text, tone: detected ? .accent : .neutral)
    }
}

// MARK: - Personalization

struct PersonalizationPane: View {
    @Bindable var model: AppModel

    @State private var newVocabulary = ""
    @State private var draftHeard = ""
    @State private var draftWritten = ""

    private var trimmedVocabulary: String {
        newVocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var draftUsable: Bool {
        !draftHeard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draftWritten.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            SettingsPaneHeader(
                title: "Personalization",
                subtitle: "Teach the recognizer your names, jargon, and preferred spellings."
            )

            SettingsGroup(
                "Vocabulary",
                icon: "text.book.closed",
                note: "Vocabulary biases Apple’s on-device recognizer and is passed to provider transcription as a prompt."
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Names and terms")
                                .font(.system(size: 12.5, weight: .medium))
                            Text("Words and names the recognizer should expect.")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        SettingsCountBadge(count: model.customVocabulary.count)
                    }

                    if model.customVocabulary.isEmpty {
                        Text("No vocabulary yet. Add names or terms below.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(model.customVocabulary, id: \.self) { word in
                                vocabularyChip(word)
                            }
                        }
                    }

                    HStack(spacing: 7) {
                        SettingsField(placeholder: "Add a name or term", text: $newVocabulary)
                            .onSubmit { submitVocabulary() }
                        Button("Add") { submitVocabulary() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(trimmedVocabulary.isEmpty)
                    }
                }
                .padding(14)

                SettingsDivider()

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("One-pass swaps")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("Left is what the model tends to hear; right is how you want it written.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }

                    if model.wordReplacements.isEmpty {
                        Text("No replacements yet.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 2)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(model.wordReplacements.enumerated()), id: \.element.id) { index, pair in
                                replacementEditor(replacementBinding(at: index))
                                if index < model.wordReplacements.count - 1 {
                                    SettingsDivider()
                                }
                            }
                        }
                    }

                    HStack(spacing: 7) {
                        SettingsField(placeholder: "Heard", text: $draftHeard)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        SettingsField(placeholder: "Write as", text: $draftWritten)
                        Button("Add") { submitReplacement() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(!draftUsable)
                    }
                }
                .padding(14)
            }

            SettingsGroup(
                "Learning",
                icon: "sparkles",
                note: "Both run on this Mac. Screen text is used for one dictation and never saved or sent to a provider."
            ) {
                SettingsRow("Names on screen", subtitle: "When you start dictating, read the focused window and expect the names in it.") {
                    SettingsToggle(isOn: $model.learnFromScreen) { _ in model.persistPreferences() }
                }

                SettingsDivider()

                SettingsRow("Learn from corrections", subtitle: "Fix a misheard name after it’s typed and it’s learned the second time. Works where the app’s text can be read.") {
                    SettingsToggle(isOn: $model.learnFromCorrections) { _ in model.persistPreferences() }
                }
            }
        }
    }

    private func vocabularyChip(_ word: String) -> some View {
        HStack(spacing: 5) {
            if model.learnedVocabulary.contains(word) {
                Image(systemName: "sparkles")
                    .font(.system(size: 8.5, weight: .semibold))
                    .help("Learned from your corrections")
            }
            Text(word)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                model.removeVocabulary(word)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7.5, weight: .bold))
                    .opacity(0.6)
            }
            .buttonStyle(.plain)
            .help("Remove from vocabulary")
        }
        .foregroundStyle(SettingsColor.accent)
        .padding(.horizontal, 8)
        .frame(height: 23)
        .background(Capsule().fill(SettingsColor.accentSoft))
        .overlay(Capsule().strokeBorder(SettingsColor.accentRing, lineWidth: 1))
    }

    private func replacementBinding(at index: Int) -> Binding<WordReplacement> {
        Binding(
            get: {
                guard model.wordReplacements.indices.contains(index) else {
                    return WordReplacement(heard: "", replacement: "")
                }
                return model.wordReplacements[index]
            },
            set: { value in
                guard model.wordReplacements.indices.contains(index) else { return }
                model.wordReplacements[index] = value
            }
        )
    }

    private func replacementEditor(_ pair: Binding<WordReplacement>) -> some View {
        HStack(spacing: 7) {
            TextField("Heard", text: pair.heard)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            TextField("Write as", text: pair.replacement)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            if pair.wrappedValue.learned == true {
                Image(systemName: "sparkles")
                    .font(.system(size: 9.5))
                    .foregroundStyle(SettingsColor.accent)
                    .help("Learned from your corrections")
            }
            Button {
                model.removeReplacement(pair.wrappedValue.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Remove replacement")
        }
        .padding(.vertical, 6)
        .onChange(of: pair.wrappedValue) { _, _ in model.personalizationChanged() }
    }

    private func submitVocabulary() {
        guard !trimmedVocabulary.isEmpty else { return }
        model.addVocabulary(trimmedVocabulary)
        newVocabulary = ""
    }

    private func submitReplacement() {
        guard model.addReplacement(heard: draftHeard, replacement: draftWritten) else { return }
        draftHeard = ""
        draftWritten = ""
    }
}

// MARK: - AI

struct AIPane: View {
    @Bindable var model: AppModel

    @State private var keyDraft = ""
    @State private var keyMessage = ""
    @State private var testMessage = ""
    @State private var testSucceeded: Bool?
    @State private var isTesting = false
    @State private var showKey = false
    @FocusState private var endpointFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsPaneHeader(
                title: "AI",
                subtitle: "One provider powers transcription, polish, generation, rewrites and connection tests. Use Apple Intelligence, your own API key, or a local model.",
                pill: aiStatusPill
            )
            .padding(.bottom, 2)

            SettingsGroup("Features", icon: "sparkles") {
                SettingsRow(
                    "Polish dictation",
                    subtitle: "Cleans filler, punctuation, and false starts after the on-device pass."
                ) {
                    SettingsToggle(isOn: $model.aiPolishEnabled) { _ in
                        model.persistPreferences()
                    }
                }

                SettingsDivider()

                SettingsRow(
                    "Rewrite selection",
                    subtitle: "Speak an instruction and rewrite selected text in place. Browsers briefly copy the selection to read it."
                ) {
                    SettingsToggle(isOn: $model.aiEnabled) { _ in
                        model.persistPreferences()
                    }
                }

                SettingsDivider()

                SettingsRow(
                    "Generate text",
                    subtitle: "Say your trigger word, then an instruction to compose something new."
                ) {
                    SettingsToggle(isOn: $model.aiGenerateEnabled) { _ in
                        model.persistPreferences()
                    }
                }

                if model.aiGenerateEnabled {
                    SettingsDivider()

                    SettingsRow(
                        "Trigger word",
                        subtitle: "The first word of the dictation."
                    ) {
                        SettingsField(placeholder: "generate", text: $model.aiGenerateTrigger)
                            .frame(width: 140)
                    }
                }
            }

            SettingsNote("Code and Terminal dictation always skip AI polish. Dictation stays on-device unless provider transcription or an AI feature is enabled.")

            SettingsGroup("Provider", icon: "server") {
                SettingsRow(
                    "Provider",
                    subtitle: "Used for polish, generation and rewrites."
                ) {
                    Picker("", selection: Binding(get: { model.aiProvider }, set: { apply($0) })) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.name).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                }

                SettingsDivider()

                if model.aiProvider == .apple {
                    appleProviderBlock
                } else {
                    SettingsRow(
                        "Endpoint",
                        subtitle: "Any OpenAI-compatible base URL."
                    ) {
                        SettingsField(placeholder: "https://api.openai.com/v1", text: $model.aiEndpoint)
                            .frame(width: 310)
                            .focused($endpointFocused)
                    }

                    SettingsDivider()

                    SettingsRow(
                        "Model",
                        subtitle: "Exact model id as the provider names it."
                    ) {
                        SettingsField(placeholder: "gpt-4.1-mini", text: $model.aiModel)
                            .frame(width: 310)
                    }

                    SettingsDivider()

                    keyBlock
                }

                SettingsDivider()

                SettingsRow(
                    "Connection",
                    subtitle: testSubtitle
                ) {
                    HStack(spacing: 8) {
                        if isTesting {
                            ProgressView().controlSize(.mini)
                        }
                        Button(isTesting ? "Testing…" : "Test") { testConnection() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(!model.aiConfigured || isTesting)
                    }
                }
            }

            if model.aiProvider != .apple {
                SettingsGroup("Transcription", icon: "waveform") {
                    if model.aiProvider.supportsProviderTranscription {
                        SettingsRow(
                            "Provider transcription",
                            subtitle: "Send recorded audio to \(model.aiProvider.name) for the final transcript. Off uses Apple’s on-device recognizer."
                        ) {
                            SettingsToggle(isOn: $model.aiTranscriptionEnabled) { _ in
                                model.persistPreferences()
                            }
                        }

                        if model.aiTranscriptionEnabled {
                            SettingsDivider()

                            SettingsRow(
                                "Transcription model",
                                subtitle: "A Whisper-compatible model id."
                            ) {
                                SettingsField(
                                    placeholder: model.aiProvider.defaultTranscriptionModel,
                                    text: $model.aiTranscriptionModel
                                )
                                .frame(width: 220)
                            }
                        }
                    } else {
                        Text("\(model.aiProvider.name) doesn’t expose audio transcription, so dictation stays with Apple’s on-device recognizer. For local Whisper, choose Custom and point it at an OpenAI-compatible server.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                    }
                }
            }

            SettingsNote(privacyNote, icon: "lock")
                .padding(.top, 2)
        }
        .onAppear {
            if model.aiKeyConfigured { keyMessage = "Saved in Keychain" }
        }
        .onChange(of: model.aiProvider) { _, _ in resetTest() }
        .onChange(of: model.aiEndpoint) { _, _ in resetTest() }
        .onChange(of: model.aiModel) { _, _ in resetTest() }
        .onChange(of: model.aiGenerateTrigger) { _, _ in model.persistPreferences() }
        .onChange(of: model.aiTranscriptionModel) { _, _ in model.persistPreferences() }
    }

    private var aiStatusPill: SettingsStatusPill {
        if model.aiProvider == .apple, !model.appleIntelligenceAvailable {
            return SettingsStatusPill(text: "Unavailable", tone: .amber)
        }
        if model.aiReady { return SettingsStatusPill(text: "Connected", tone: .green) }
        if model.aiConfigured { return SettingsStatusPill(text: "Ready", tone: .accent) }
        return SettingsStatusPill(text: "Off", tone: .neutral)
    }

    private var appleProviderBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Apple Intelligence")
                    .font(.system(size: 13, weight: .medium))
                Text(model.appleIntelligenceStatus)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Runs on this Mac through the Foundation Models framework.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            SettingsStatusPill(
                text: model.appleIntelligenceAvailable ? "Available" : "Unavailable",
                tone: model.appleIntelligenceAvailable ? .green : .amber
            )
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    private var keyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("API key")
                    .font(.system(size: 13, weight: .medium))
                Text(keyStatus)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 7) {
                Group {
                    if showKey {
                        TextField(keyPlaceholder, text: $keyDraft)
                    } else {
                        SecureField(keyPlaceholder, text: $keyDraft)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 9)
                .frame(maxWidth: .infinity)
                .frame(height: 27)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(SettingsColor.field)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(SettingsColor.borderStrong, lineWidth: 1)
                )

                Button {
                    showKey.toggle()
                } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(showKey ? "Hide API key" : "Show API key")

                Button("Save") { saveKey() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if model.aiKeyConfigured {
                    Button("Remove") { removeKey() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    private var testSubtitle: String {
        if model.aiProvider == .apple {
            if isTesting { return "Reaching Apple Intelligence…" }
            if !testMessage.isEmpty { return testMessage }
            return "Runs entirely on this Mac"
        }
        if isTesting { return "Reaching \(model.settingsProviderHost)…" }
        if !testMessage.isEmpty { return testMessage }
        return "Requests go straight to \(model.settingsProviderHost)"
    }

    private var privacyNote: String {
        if model.providerTranscriptionActive {
            return "Audio is sent to \(model.settingsProviderName) for transcription. Text is sent only when an AI feature runs."
        }
        if model.aiProvider == .apple {
            return "Only text is processed on-device by Apple Intelligence. Audio never leaves this Mac."
        }
        return "Only text is sent to \(model.settingsProviderName). Audio never leaves this Mac."
    }

    private func apply(_ provider: AIProvider) {
        model.selectAIProvider(provider)
        if provider == .custom {
            endpointFocused = true
        }
    }

    private var keyPlaceholder: String {
        model.aiKeyConfigured ? "Saved — enter a new key to replace it" : "Paste your key"
    }

    private var keyStatus: String {
        if !keyMessage.isEmpty { return keyMessage }
        if model.aiKeyConfigured { return "Saved in Keychain" }
        if AIService.isLocalEndpoint(model.aiEndpoint) { return "No key needed for a local endpoint" }
        return "No key saved"
    }

    private func saveKey() {
        if model.saveAIKey(keyDraft) {
            keyDraft = ""
            keyMessage = "Saved in Keychain"
            testMessage = ""
            testSucceeded = nil
        } else {
            keyMessage = "Couldn’t save that key"
        }
    }

    private func removeKey() {
        model.removeAIKey()
        keyDraft = ""
        keyMessage = "Key removed"
        testMessage = ""
        testSucceeded = nil
    }

    private func testConnection() {
        guard !isTesting else { return }
        isTesting = true
        testMessage = ""
        testSucceeded = nil
        Task {
            let result = await model.testAIConnection()
            await MainActor.run {
                testMessage = result
                testSucceeded = result.hasPrefix("Connected")
                isTesting = false
            }
        }
    }

    private func resetTest() {
        testMessage = ""
        testSucceeded = nil
        keyMessage = ""
        model.persistPreferences()
    }
}

// MARK: - Output

struct OutputPane: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            SettingsPaneHeader(
                title: "Output",
                subtitle: "Where the text goes, how it gets there, and what you see while talking."
            )

            SettingsGroup("Insertion", icon: "text.cursor", note: insertionNote) {
                SettingsRow("Type into the frontmost app", subtitle: "Finishing a dictation inserts the cleaned text at the cursor.") {
                    SettingsToggle(isOn: $model.autoInsert) { _ in model.persistPreferences() }
                }

                SettingsDivider()

                SettingsRow("Insert without the clipboard", subtitle: "Tries Accessibility, then synthetic typing, and pastes only if both fail.") {
                    SettingsToggle(isOn: $model.useDirectInsertion) { _ in model.persistPreferences() }
                }

                SettingsDivider()

                pipeline
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }

            SettingsGroup("Overlay", icon: "rectangle.on.rectangle") {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Style")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("Shown while listening and just after the text lands.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        model.previewOverlay()
                    } label: {
                        Label("Preview", systemImage: "play.fill")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

                SettingsDivider()

                HStack(spacing: 9) {
                    overlayTile(.capsule)
                    overlayTile(.card)
                }
                .padding(10)
            }
        }
    }

    private var insertionNote: String {
        if !model.autoInsert {
            return "Automatic insertion is off. Dictations stay in the overlay and history so you can copy them manually."
        }
        if model.useDirectInsertion {
            return "Browsers, Notes, Slack and other Electron apps get a paste instead, because they drop direct writes. Pastes are marked private so clipboard managers that respect it skip them, and your previous clipboard is put back."
        }
        return "Every insertion uses the clipboard and a synthesized ⌘V. Your previous clipboard is restored, but clipboard managers may record dictations."
    }

    private var pipeline: some View {
        HStack(spacing: 5) {
            pipelineNode(
                title: "Accessibility", subtitle: "Direct write", icon: "person.crop.circle",
                active: model.autoInsert && model.useDirectInsertion
            )
            arrow
            pipelineNode(
                title: "Typing", subtitle: "Synthetic keys", icon: "keyboard",
                active: model.autoInsert && model.useDirectInsertion
            )
            arrow
            pipelineNode(
                title: "Paste", subtitle: "Fallback only", icon: "doc.on.clipboard",
                active: model.autoInsert && !model.useDirectInsertion
            )
        }
    }

    private func pipelineNode(title: String, subtitle: String, icon: String, active: Bool) -> some View {
        HStack(spacing: 7) {
            SettingsIconTile(
                symbol: icon,
                tint: active ? SettingsColor.accent : SettingsColor.faintText,
                size: 24
            )
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(active ? SettingsColor.accentSoft : SettingsColor.cardMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(active ? SettingsColor.accentRing : SettingsColor.border, lineWidth: 1)
        )
        .opacity(active ? 1 : 0.65)
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.tertiary)
    }

    private func overlayTile(_ style: AppModel.OverlayStyle) -> some View {
        let selected = model.overlayStyle == style
        return Button {
            model.overlayStyle = style
            model.persistPreferences()
            model.previewOverlay()
        } label: {
            VStack(spacing: 0) {
                SettingsOverlayThumbnail(style: style)
                    .padding(5)

                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(style.label)
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(style.detail)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(SettingsColor.accent)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SettingsColor.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? SettingsColor.accent : SettingsColor.border,
                                  lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - History

struct HistoryPane: View {
    @Bindable var model: AppModel

    @State private var search = ""
    @State private var showAll = false
    @State private var confirmClear = false

    private var query: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filtered: [DictationRecord] {
        var records = model.history
        if !query.isEmpty {
            let needle = query.lowercased()
            records = records.filter {
                $0.text.lowercased().contains(needle) || $0.appName.lowercased().contains(needle)
            }
        } else if !showAll {
            records = Array(records.prefix(8))
        }
        return records
    }

    private var olderCount: Int {
        max(model.history.count - 8, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            SettingsPaneHeader(
                title: "History",
                subtitle: "Dictations saved on this Mac so you can recover them after the overlay fades."
            )

            SettingsGroup("Recent", icon: "clock.arrow.circlepath") {
                SettingsRow("Keep a local history", subtitle: "History keeps text only. Audio is never stored in it.") {
                    SettingsToggle(isOn: $model.historyEnabled) { _ in model.historySettingChanged() }
                }

                SettingsDivider()

                searchBar

                if model.history.isEmpty {
                    SettingsEmptyState(
                        icon: "clock",
                        title: "No dictations yet",
                        message: "Finished dictations will appear here."
                    )
                } else if filtered.isEmpty {
                    SettingsEmptyState(
                        icon: "magnifyingglass",
                        title: "No matches",
                        message: "Nothing matches “\(query)”."
                    )
                } else {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, record in
                        if index > 0 { SettingsDivider() }
                        HistoryRow(record: record,
                                   onCopy: { model.copyHistory(record) },
                                   onDelete: { model.deleteHistory(record) })
                    }
                }

                SettingsDivider()

                if confirmClear {
                    HStack(spacing: 8) {
                        Text("Delete all \(model.history.count) dictations? This can’t be undone.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { confirmClear = false }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("Delete all") {
                            model.clearHistory()
                            confirmClear = false
                            showAll = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SettingsColor.red)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(SettingsColor.cardMuted)
                } else {
                    HStack(spacing: 8) {
                        Text(historySummary)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if olderCount > 0 && query.isEmpty {
                            Button(showAll ? "Show less" : "Show \(olderCount) older") {
                                withAnimation(.easeOut(duration: 0.15)) { showAll.toggle() }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(SettingsColor.accent)
                        }
                        if !model.history.isEmpty {
                            Button("Clear") { confirmClear = true }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            TextField("Search dictations", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(SettingsColor.field)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(SettingsColor.borderStrong, lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(SettingsColor.cardMuted)
    }

    private var historySummary: String {
        guard !model.history.isEmpty else { return "Nothing saved" }
        let count = model.history.count
        let noun = count == 1 ? "dictation" : "dictations"
        return model.historyEnabled
            ? "\(count) \(noun) saved on this Mac"
            : "\(count) \(noun) saved \u{00b7} recording paused"
    }
}

private struct HistoryRow: View {
    let record: DictationRecord
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(SettingsAppMonogram.tint(record.appName))
                .frame(width: 21, height: 21)
                .overlay(
                    Text(SettingsAppMonogram.initial(record.appName))
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(record.text)
                    .font(.system(size: 11.5))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(record.appName) \u{00b7} \(relative)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            HStack(spacing: 2) {
                iconButton("doc.on.doc", help: "Copy this dictation", action: onCopy)
                iconButton("trash", help: "Delete this dictation", action: onDelete)
            }
            .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private func iconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 21, height: 21)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var relative: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: record.date, relativeTo: Date())
    }
}

// MARK: - Permissions

struct PermissionsPane: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsPaneHeader(
                title: "Permissions",
                subtitle: "QuietSpeech needs the microphone and Accessibility to work.",
                pill: SettingsStatusPill(
                    text: model.settingsSetupComplete ? "All granted" : "Setup needed",
                    tone: model.settingsSetupComplete ? .green : .amber
                )
            )
            .padding(.bottom, 2)

            SettingsGroup("Access", icon: "lock.shield",
                          note: "macOS reads permissions per process. If you change one in System Settings, relaunch QuietSpeech afterwards.") {
                permissionRow(
                    title: "Microphone",
                    detail: "Listens only while dictation is active.",
                    granted: model.microphoneGranted
                ) {
                    Task {
                        _ = await Permissions.requestMicrophone()
                        model.refreshPermissions()
                    }
                } manage: {
                    openPrivacy("Privacy_Microphone")
                }

                SettingsDivider()

                permissionRow(
                    title: "Accessibility",
                    detail: "Needed for global shortcuts and inserting text at the cursor.",
                    granted: model.accessibilityGranted
                ) {
                    model.requestAccessibility()
                } manage: {
                    openPrivacy("Privacy_Accessibility")
                }
            }

            SettingsGroup("After changes", icon: "power") {
                SettingsRow("Recheck permissions", subtitle: "Refresh the status after changing them in System Settings.") {
                    Button("Recheck") { model.refreshPermissions() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                SettingsDivider()

                SettingsRow("Restart the app", subtitle: "Applies permission changes immediately without touching your settings.") {
                    Button("Relaunch") { model.relaunch() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }

    private func permissionRow(
        title: String, detail: String, granted: Bool,
        grant: @escaping () -> Void, manage: @escaping () -> Void
    ) -> some View {
        SettingsRow(
            title,
            subtitle: detail,
            trailing: {
                HStack(spacing: 7) {
                    SettingsStatusPill(text: granted ? "Granted" : "Needed",
                                       tone: granted ? .green : .amber)
                    Button(granted ? "Manage" : "Grant") {
                        granted ? manage() : grant()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        )
    }

    private func openPrivacy(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Privacy

struct PrivacyPane: View {
    @Bindable var model: AppModel
    var navigate: (SettingsPane) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            SettingsPaneHeader(
                title: "Privacy",
                subtitle: "What is stored locally, and what leaves your Mac.",
                pill: SettingsStatusPill(
                    text: model.providerTranscriptionActive
                        ? "Local + provider audio"
                        : (model.aiReady
                            ? (model.aiRunsOnDevice ? "On-device" : "Local + API key")
                            : "Local first"),
                    tone: .accent
                )
            )

            SettingsGroup(model.providerTranscriptionActive ? "On this Mac and provider" : "On this Mac", icon: "shield") {
                SettingsRow("Dictation history", subtitle: "The text of each finished dictation, kept for recovery.") {
                    SettingsToggle(isOn: $model.historyEnabled) { _ in model.historySettingChanged() }
                }

                if AppModel.developerToolsEnabled {
                    SettingsDivider()

                    SettingsRow("Review cleanup", subtitle: "Appends raw and cleaned text to a file so you can compare them.") {
                        SettingsToggle(isOn: $model.captureDictations) { _ in
                            model.persistPreferences()
                            model.refreshCaptureStatus()
                        }
                    }
                }

                // Without developer tools, a file left by an earlier version
                // can still be deleted.
                if AppModel.developerToolsEnabled || model.settingsCaptureFileExists {
                    SettingsDivider()

                    SettingsRow("Capture file", subtitle: model.captureStatus) {
                        HStack(spacing: 7) {
                            Button("Reveal") { model.revealCaptureFile() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(!model.settingsCaptureFileExists)
                            Button("Delete") {
                                model.clearCaptureFile()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(SettingsColor.red)
                            .disabled(!model.settingsCaptureFileExists)
                        }
                    }
                }

                SettingsDivider()

                SettingsRow("Audio recordings", subtitle: audioStorageDetail) {
                    SettingsStatusPill(
                        text: model.providerTranscriptionActive ? "Temporary" : "Not saved",
                        tone: .neutral
                    )
                }
            }

            SettingsGroup(model.aiRunsOnDevice ? "AI processing" : "Leaves this Mac", icon: "arrow.up.right") {
                SettingsRow("AI requests", subtitle: aiRequestDetail) {
                    SettingsStatusPill(
                        text: model.providerTranscriptionActive
                            ? "Audio + text"
                            : (model.aiReady ? (model.aiRunsOnDevice ? "On-device" : "Only when enabled") : "Off"),
                        tone: model.aiReady ? .green : .neutral
                    )
                }

                SettingsDivider()

                SettingsRow("Provider", subtitle: providerPrivacyDetail) {
                    HStack(spacing: 7) {
                        if model.aiConfigured {
                            SettingsStatusPill(
                                text: model.aiProvider == .apple
                                    ? "Apple Intelligence \u{00b7} this Mac"
                                    : "\(model.settingsProviderName) \u{00b7} \(model.settingsProviderHost)",
                                tone: .neutral
                            )
                        }
                        Button("Manage") { navigate(.ai) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                SettingsDivider()

                SettingsRow("Analytics and accounts", subtitle: "No account and no analytics. The app only checks your license with Polar and looks for updates on quietspeech.app.") {
                    SettingsStatusPill(text: "None", tone: .neutral)
                }
            }

            SettingsNote("Deleting the app leaves its data behind, so clear History first. An AI key is removed from the AI screen.")
        }
    }

    private var aiRequestDetail: String {
        if model.providerTranscriptionActive {
            return "Audio goes to \(model.settingsProviderName) for transcription; text for AI features."
        }
        if model.aiProvider == .apple {
            return "Text is processed on-device by Apple Intelligence."
        }
        return "Only the text you dictated or selected is sent to your provider."
    }

    private var audioStorageDetail: String {
        if model.providerTranscriptionActive {
            return "A temporary audio file is written, sent to \(model.settingsProviderName), then deleted."
        }
        return "Audio is transcribed in memory and discarded. It is never written to disk."
    }

    private var providerPrivacyDetail: String {
        if model.aiProvider == .apple {
            return "Apple Intelligence runs on this Mac. No key or endpoint is needed."
        }
        return "Configured under AI. Keys live in the macOS Keychain."
    }
}
