import SwiftUI
import AppKit

/// Shown once, in the app's only window: the two permissions the app cannot work
/// without, the activation key, and the overlay style — then it hands the window
/// over to the settings form.
struct OnboardingView: View {
    @Bindable var model: AppModel
    @State private var step = 0

    private let lastStep = 4
    private let stepTitles = ["Welcome", "Microphone", "Accessibility", "Your key", "Overlay"]

    var body: some View {
        VStack(spacing: 0) {
            progress

            GeometryReader { proxy in
                ScrollView {
                    content
                        .padding(.horizontal, 30)
                        .padding(.vertical, 22)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity))
                }
                .animation(.snappy(duration: 0.26), value: step)
            }

            Divider()
            footer
        }
        .frame(width: 620, height: 580)
        .background(
            LinearGradient(colors: [Color.accentColor.opacity(0.07), .clear],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        )
        .onAppear { model.refreshPermissions() }
        .onChange(of: step) { _, _ in model.refreshPermissions() }
    }

    // MARK: - Chrome

    private var progress: some View {
        VStack(spacing: 9) {
            HStack(spacing: 5) {
                ForEach(0...lastStep, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Color.accentColor : Color.primary.opacity(0.12))
                        .frame(height: 4)
                }
            }

            HStack {
                Text(stepTitles[step])
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Step \(step + 1) of \(lastStep + 1)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 22)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if step > 0, step < lastStep, !canAdvance {
                Button("Skip for now") { step += 1 }
                    .buttonStyle(.link)
            }

            Spacer()

            if step > 0 {
                Button("Back") { step -= 1 }
                    .controlSize(.large)
            }

            if step < lastStep {
                Button(step == 0 ? "Get started" : "Continue") { step += 1 }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdvance)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Start dictating") {
                    model.completeOnboarding()
                    NSApp.keyWindow?.close()
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 18)
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
        VStack(alignment: .leading, spacing: 18) {
            IconTile(symbol: "waveform", size: 52)

            VStack(alignment: .leading, spacing: 10) {
                Text("Whispr Proto")
                    .font(.system(size: 27, weight: .bold))
                Text("Hold a key, speak, and your words appear in whatever app you're using — punctuated, capitalised and cleaned up.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                feature("text.bubble.fill", "Speech becomes text",
                        "Apple's on-device recogniser. No network needed.")
                feature("wand.and.stars", "Cleanup by rules",
                        "Deterministic, so it can never invent words you didn't say.")
                feature("lock.fill", "Private by design",
                        "Audio and text never leave this Mac.")
            }
        }
    }

    private var microphone: some View {
        stepScaffold(
            symbol: "mic.fill",
            title: "Microphone",
            subtitle: "Whispr Proto listens only while you hold the key. Nothing is recorded to disk."
        ) {
            permissionCard(
                title: "Microphone access",
                detail: "Lets the app hear you while dictating.",
                granted: model.microphoneGranted
            ) {
                Button("Allow access") {
                    Task { _ = await Permissions.requestMicrophone(); model.refreshPermissions() }
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var accessibility: some View {
        stepScaffold(
            symbol: "lock.shield.fill",
            title: "Accessibility",
            subtitle: "To type into other apps, macOS asks you to grant Accessibility access to Whispr Proto."
        ) {
            permissionCard(
                title: "Accessibility access",
                detail: "Lets your words land in the app you're using.",
                granted: model.accessibilityGranted
            ) {
                HStack(spacing: 8) {
                    Button("Open Settings") { model.requestAccessibility() }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                    Button("Recheck") { model.refreshPermissions() }
                        .controlSize(.large)
                }
            }

            Text("Add Whispr Proto under Privacy & Security › Accessibility, then come back here. If it's listed and still not working, quit and reopen the app.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var chooseKey: some View {
        stepScaffold(
            symbol: "command",
            title: "Choose your key",
            subtitle: "Pick how you start and stop dictating."
        ) {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hold to talk").font(.callout.weight(.medium))
                            Text("Speak while the keys are down.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        ShortcutRecorder(binding: holdBinding,
                                         onCaptureStateChanged: { model.setShortcutCapture($0) }) {
                            model.applyActivation()
                            model.refreshPermissions()
                        }
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tap to toggle").font(.callout.weight(.medium))
                            Text("Press once to start, again to stop.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        ShortcutRecorder(binding: toggleBinding,
                                         onCaptureStateChanged: { model.setShortcutCapture($0) }) {
                            model.applyActivation()
                            model.refreshPermissions()
                        }
                    }
                }
            }

            if model.shortcutConfiguration.hold.usesFnKey || model.shortcutConfiguration.toggle.usesFnKey {
                hint("If Fn opens the emoji picker, set “Press 🌐 key to” to “Do nothing” in System Settings › Keyboard.")
            }

            Card {
                HStack(spacing: 14) {
                    WaveformView(levels: model.levels, level: model.level, idle: !model.isRecording)
                        .frame(width: 96, height: 34)
                    Text(testStatus)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var chooseStyle: some View {
        stepScaffold(
            symbol: "rectangle.on.rectangle.angled",
            title: "Overlay",
            subtitle: "What you see on screen while you dictate. You can change this any time in Settings."
        ) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(AppModel.OverlayStyle.allCases) { style in
                    styleCard(style)
                }
            }

            Button("Preview on screen") { model.previewOverlay() }
                .controlSize(.large)
        }
    }

    // MARK: - Pieces

    private func stepScaffold<Content: View>(symbol: String, title: String, subtitle: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            IconTile(symbol: symbol, size: 46)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        Card {
            HStack(spacing: 14) {
                IconTile(symbol: symbol, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func permissionCard<Actions: View>(title: String, detail: String, granted: Bool,
                                               @ViewBuilder actions: () -> Actions) -> some View {
        Card(selected: granted) {
            HStack(spacing: 14) {
                Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 22))
                    .foregroundStyle(granted ? Color.green : Color.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.semibold))
                    Text(granted ? "Granted" : detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if !granted { actions() }
            }
        }
    }

    private func styleCard(_ style: AppModel.OverlayStyle) -> some View {
        let selected = model.overlayStyle == style
        return Button {
            model.overlayStyle = style
            model.persistPreferences()
        } label: {
            Card(selected: selected) {
                VStack(alignment: .leading, spacing: 12) {
                    OverlayThumbnail(style: style)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(style.label).font(.callout.weight(.semibold))
                            if selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        Text(style.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func hint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
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

/// Miniature of the real overlay, drawn with the same waveform component.
private struct OverlayThumbnail: View {
    let style: AppModel.OverlayStyle

    private let demo: [Float] = [0.30, 0.72, 0.45, 0.90, 0.55, 0.80, 0.35,
                                 0.66, 0.50, 0.86, 0.40, 0.62, 0.30, 0.75]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
            content
        }
        .frame(height: 76)
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .capsule:
            HStack(spacing: 8) {
                Circle().fill(Color.red).frame(width: 5, height: 5)
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
                    Circle().fill(Color.red).frame(width: 5, height: 5)
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
