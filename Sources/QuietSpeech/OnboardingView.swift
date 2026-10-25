import SwiftUI
import AppKit

/// Shown once, in the app's only window: the two permissions the app cannot work
/// without, the activation key, and the overlay style — then it hands the window
/// over to the settings form.
struct OnboardingView: View {
    @Bindable var model: AppModel
    var onFinish: (() -> Void)?
    @State private var step = 0

    private let lastStep = 4
    private let stepTitles = ["Welcome", "Microphone", "Accessibility", "Your key", "Overlay"]

    var body: some View {
        VStack(spacing: 0) {
            progress

            GeometryReader { proxy in
                ScrollView {
                    content
                        .frame(maxWidth: 500, alignment: .leading)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 22)
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity))
                }
                .animation(.snappy(duration: 0.26), value: step)
            }

            SettingsDivider()
            footer
        }
        .frame(width: 620, height: 580)
        .background(SettingsColor.window)
        .tint(SettingsColor.accent)
        .onAppear { model.refreshPermissions() }
        .onChange(of: step) { _, _ in model.refreshPermissions() }
    }

    // MARK: - Chrome

    private var progress: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                ForEach(0...lastStep, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? SettingsColor.accent : Color.primary.opacity(0.11))
                        .frame(height: 4)
                }
            }

            HStack {
                Text(stepTitles[step])
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Step \(step + 1) of \(lastStep + 1)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 26)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if step > 0, step < lastStep, !canAdvance {
                Button("Skip for now") { step += 1 }
                    .buttonStyle(.link)
            }

            Spacer()

            if step > 0 {
                Button("Back") { step -= 1 }
                    .controlSize(.regular)
            }

            if step < lastStep {
                Button {
                    step += 1
                } label: {
                    Text(step == 0 ? "Get started" : "Continue")
                        .foregroundStyle(SettingsColor.onAccent)
                }
                .controlSize(.regular)
                .buttonStyle(.borderedProminent)
                .tint(SettingsColor.accentFill)
                .disabled(!canAdvance)
                .keyboardShortcut(.defaultAction)
            } else {
                Button {
                    model.completeOnboarding()
                    onFinish?()
                } label: {
                    Text("Finish setup")
                        .foregroundStyle(SettingsColor.onAccent)
                }
                .controlSize(.regular)
                .buttonStyle(.borderedProminent)
                .tint(SettingsColor.accentFill)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 14)
    }

    private var canAdvance: Bool {
        switch step {
        case 1: return model.microphoneGranted
        case 2: return model.accessibilityGranted
        default: return true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcome
        case 1: microphone
        case 2: accessibility
        case 3: chooseKey
        default: chooseStyle
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        stepScaffold(
            symbol: "waveform",
            title: "QuietSpeech",
            subtitle: "Hold a key, speak, and your words appear in whatever app you’re using — punctuated, capitalised and cleaned up.",
            brand: true
        ) {
            SettingsCard {
                feature("text.bubble", "Speech becomes text",
                        "Apple’s on-device recogniser. No network needed.")
                SettingsDivider()
                feature("wand.and.stars", "Cleanup by rules",
                        "Deterministic, so it can never invent words you didn’t say.")
                SettingsDivider()
                feature("lock", "Private by design",
                        "Audio and text never leave this Mac.")
            }

            if model.license.isConfigured {
                SettingsNote(
                    "QuietSpeech is a one-time purchase. Buy once, then activate this Mac with your license key.",
                    icon: "key"
                )
                .padding(.horizontal, 2)
            }

            SettingsNote("Every setting can be changed later in Settings.", icon: "gearshape")
                .padding(.horizontal, 2)
        }
    }

    private var microphone: some View {
        stepScaffold(
            symbol: "mic.fill",
            title: "Microphone",
            subtitle: "QuietSpeech listens only while you hold the key. Nothing is recorded to disk."
        ) {
            SettingsCard {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Microphone access")
                            .font(.system(size: 13, weight: .medium))
                        Text("Lets the app hear you while dictating.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 10)
                    if model.microphoneGranted {
                        SettingsStatusPill(text: "Granted", tone: .green)
                    } else {
                        Button {
                            Task {
                                _ = await Permissions.requestMicrophone()
                                model.refreshPermissions()
                            }
                        } label: {
                            Text("Allow access")
                                .foregroundStyle(SettingsColor.onAccent)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SettingsColor.accentFill)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
            }

            SettingsNote("macOS asks once. You can revoke access later in System Settings.", icon: "lock")
                .padding(.horizontal, 2)
        }
    }

    private var accessibility: some View {
        stepScaffold(
            symbol: "lock.shield.fill",
            title: "Accessibility",
            subtitle: "To type into other apps, macOS asks you to grant Accessibility access to QuietSpeech."
        ) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accessibility access")
                                .font(.system(size: 13, weight: .medium))
                            Text("Lets your words land in the app you’re using.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 10)
                        if model.accessibilityGranted {
                            SettingsStatusPill(text: "Granted", tone: .green)
                        }
                    }

                    if !model.accessibilityGranted {
                        HStack(spacing: 8) {
                            Button {
                                model.requestAccessibility()
                            } label: {
                                Text("Open Settings")
                                    .foregroundStyle(SettingsColor.onAccent)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(SettingsColor.accentFill)
                            .controlSize(.small)

                            Button("Recheck") { model.refreshPermissions() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
            }

            SettingsNote("Add QuietSpeech under Privacy & Security › Accessibility, then come back here. If it’s listed and still not working, quit and reopen the app.")
                .padding(.horizontal, 2)
        }
    }

    private var chooseKey: some View {
        stepScaffold(
            symbol: "command",
            title: "Choose your key",
            subtitle: "Pick how you start and stop dictating. You can change this later in Settings."
        ) {
            SettingsCard {
                shortcutRow(
                    title: "Hold to talk",
                    detail: "Speak while the keys are down.",
                    binding: holdBinding
                )
                SettingsDivider()
                shortcutRow(
                    title: "Tap to toggle",
                    detail: "Press once to start, again to stop.",
                    binding: toggleBinding
                )
            }

            if model.shortcutConfiguration.hold.usesFnKey || model.shortcutConfiguration.toggle.usesFnKey {
                SettingsNote("If Fn opens the emoji picker, set “Press 🌐 key to” to “Do nothing” in System Settings › Keyboard.")
                    .padding(.horizontal, 2)
            }

            SettingsCard {
                HStack(spacing: 13) {
                    WaveformView(levels: model.levels, level: model.level, idle: !model.isRecording)
                        .frame(width: 96, height: 30)
                    Text(testStatus)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
            }
        }
    }

    private var chooseStyle: some View {
        stepScaffold(
            symbol: "rectangle.on.rectangle.angled",
            title: "Overlay",
            subtitle: "What you see on screen while you dictate. You can change this any time in Settings."
        ) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(AppModel.OverlayStyle.allCases) { style in
                    styleCard(style)
                }
            }

            Button("Preview on screen") { model.previewOverlay() }
                .buttonStyle(.bordered)
                .controlSize(.regular)
        }
    }

    // MARK: - Pieces

    private func stepScaffold<Content: View>(
        symbol: String,
        title: String,
        subtitle: String,
        brand: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingIcon(symbol: symbol, brand: brand)

            Text(title)
                .font(.system(size: 24, weight: .bold))
                .padding(.top, 15)

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(.top, 18)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SettingsColor.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    private func shortcutRow(
        title: String,
        detail: String,
        binding: Binding<ShortcutBinding>
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 10)
            ShortcutRecorder(binding: binding,
                             onCaptureStateChanged: { model.setShortcutCapture($0) }) {
                model.applyActivation()
                model.refreshPermissions()
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    private func styleCard(_ style: AppModel.OverlayStyle) -> some View {
        let selected = model.overlayStyle == style
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button {
            model.overlayStyle = style
            model.persistPreferences()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                OverlayThumbnail(style: style)

                HStack(spacing: 6) {
                    Text(style.label)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 4)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsColor.accent)
                    }
                }

                Text(style.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(SettingsColor.card))
            .overlay(
                shape.strokeBorder(selected ? SettingsColor.accent : SettingsColor.border,
                                   lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var testStatus: String {
        if model.isRecording { return "Listening — say something." }
        if !model.rawText.isEmpty { return "Heard: \(model.rawText)" }
        let configuration = model.shortcutConfiguration
        if configuration.isDisabled {
            return "Activation is off — start dictation from the menu bar."
        }
        if !configuration.hold.isDisabled {
            return "Hold \(configuration.hold.displayName) to try it."
        }
        return "Press \(configuration.toggle.displayName) to try it."
    }

    private var holdBinding: Binding<ShortcutBinding> {
        Binding(
            get: { model.shortcutConfiguration.hold },
            set: { model.setBinding($0, for: .hold) }
        )
    }

    private var toggleBinding: Binding<ShortcutBinding> {
        Binding(
            get: { model.shortcutConfiguration.toggle },
            set: { model.setBinding($0, for: .toggle) }
        )
    }
}

// MARK: - Pieces

private struct OnboardingIcon: View {
    let symbol: String
    var brand = false

    private var appIcon: NSImage {
        if let icon = NSApp.applicationIconImage { return icon }
        if let icon = NSImage(named: "AppIcon") { return icon }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) { return icon }
        return BrandMark.image(size: 52)
    }

    var body: some View {
        if brand {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 52, height: 52)
        } else {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(SettingsColor.accentSoft)
                .frame(width: 52, height: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(SettingsColor.accent.opacity(0.14), lineWidth: 1)
                )
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(SettingsColor.accent)
                }
        }
    }
}

/// Miniature of the real overlay, drawn with the same waveform component.
private struct OverlayThumbnail: View {
    let style: AppModel.OverlayStyle

    private let demo: [Float] = [0.30, 0.72, 0.45, 0.90, 0.55, 0.80, 0.35,
                                 0.66, 0.50, 0.86, 0.40, 0.62, 0.30, 0.75]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.094, green: 0.106, blue: 0.125))
            content
        }
        .frame(height: 76)
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .capsule:
            HStack(spacing: 8) {
                Circle().fill(SettingsColor.accent).frame(width: 5, height: 5)
                WaveformView(levels: demo, level: 0.6, barCount: 10,
                             fixedBarWidth: 2, spacing: 2)
                    .frame(width: 42, height: 15)
                Text("Listening")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.black.opacity(0.85)))

        case .card:
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Circle().fill(SettingsColor.accent).frame(width: 5, height: 5)
                    Text("Slack")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer(minLength: 16)
                }
                WaveformView(levels: demo, level: 0.6, barCount: 16,
                             fixedBarWidth: 2, spacing: 2)
                    .frame(width: 84, height: 13)
            }
            .padding(10)
            .frame(width: 134)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.85)))
        }
    }
}
