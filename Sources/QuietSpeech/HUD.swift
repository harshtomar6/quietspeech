import SwiftUI
import AppKit

// MARK: - Palette

private enum OverlayPalette {
    static let accent = SettingsColor.accent
    static let warn = SettingsColor.amber
    static let success = SettingsColor.green
}

extension AppModel.OverlayStyle {
    /// Size of the visible overlay. The panel is larger by the shadow bleed.
    var contentSize: CGSize {
        switch self {
        case .capsule: return CGSize(width: 380, height: 54)
        case .card:    return CGSize(width: 360, height: 102)
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .capsule: return 27
        case .card:    return 16
        }
    }
}

// MARK: - Overlay-facing state

private extension AppModel {
    var overlayLevels: [Float] { previewLevels ?? levels }

    var overlayDotColor: Color {
        switch overlayPhase {
        case .listening: return OverlayPalette.accent
        case .processing: return OverlayPalette.warn
        case .done: return OverlayPalette.success
        case .error: return SettingsColor.red
        }
    }

    var overlayStateLabel: String {
        switch overlayPhase {
        case .listening: return isEditSession ? "Editing" : "Listening"
        case .processing:
            switch aiProcessing {
            case .polish: return "Polishing"
            case .edit: return "Rewriting"
            case .generate: return "Generating"
            case .transcribe: return "Transcribing"
            case nil: return "Finishing"
            }
        case .done:
            if isGenerateSession { return "Generated" }
            return isEditSession ? "Rewritten" : (autoInsert ? "Inserted" : "Ready")
        case .error: return "Error"
        }
    }

    /// Name of the app the transcript will be typed into.
    var overlayTargetAppName: String {
        targetApp?.localizedName ?? "Frontmost app"
    }

    /// What to show as the live transcript: the polished text once it exists,
    /// otherwise the raw transcript. The preview overrides both.
    var overlayLiveText: String {
        if let previewText { return previewText }
        let source = cleanedText.isEmpty ? rawText : cleanedText
        return source.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var overlayPlaceholder: String {
        switch overlayPhase {
        case .listening: return isEditSession ? "Say how to change it…" : "Speak now…"
        case .processing:
            switch aiProcessing {
            case .polish: return "Polishing the dictation…"
            case .edit: return "Rewriting the selection…"
            case .generate: return "Writing with AI…"
            case .transcribe: return "Transcribing with \(aiProvider.name)…"
            case nil: return "Finishing…"
            }
        case .done:
            if isGenerateSession { return "Generated" }
            return isEditSession ? "Rewritten" : "Done"
        case .error: return "Couldn't finish"
        }
    }

    var overlayElapsedLabel: String {
        let total = Int(overlayElapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - View

/// The always-on-top, click-through overlay shown while dictating.
struct HUDView: View {
    let model: AppModel

    /// Room reserved around the overlay so the SwiftUI shadow isn't clipped by
    /// the borderless panel's bounds.
    static let shadowBleed: CGFloat = 30

    var body: some View {
        overlay
            .padding(Self.shadowBleed)
    }

    @ViewBuilder
    private var overlay: some View {
        if let notice = model.learningNotice, !model.isRecording {
            LearningNoticeOverlay(text: notice, style: model.overlayStyle)
        } else {
            switch model.overlayStyle {
            case .capsule: CapsuleOverlay(model: model)
            case .card:    CardOverlay(model: model)
            }
        }
    }
}

// MARK: - Learning notice

/// A short line saying which corrected words were learned. Sits where the
/// dictation overlay does, sized to fit inside the same panel.
private struct LearningNoticeOverlay: View {
    let text: String
    let style: AppModel.OverlayStyle

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OverlayPalette.accent)
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(Color.primary.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .modifier(OverlaySurface(cornerRadius: 20, restartToken: nil))
        .frame(width: style.contentSize.width, height: style.contentSize.height, alignment: .bottom)
    }
}

// MARK: - Glass surface

private struct OverlaySurface: ViewModifier {
    let cornerRadius: CGFloat
    /// Re-plays the entrance animation whenever this changes (each new session).
    let restartToken: Date?

    @State private var shown = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(SettingsColor.overlayBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.34), radius: 16, y: 7)
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.985)
            .offset(y: shown ? 0 : 5)
            .onAppear { play() }
            .onChange(of: restartToken) { _, _ in play() }
    }

    private func play() {
        shown = false
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) { shown = true }
        }
    }
}

// MARK: - 1 · Capsule

/// One slim line: target app icon, level meter, live text, timer.
private struct CapsuleOverlay: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 9) {
            TargetAppIcon(app: model.targetApp,
                          name: model.overlayTargetAppName,
                          isError: model.overlayPhase == .error)

            PulseDot(color: model.overlayDotColor,
                     active: model.overlayPhase == .listening,
                     size: 6)

            WaveformView(levels: model.overlayLevels,
                         level: model.previewLevel ?? model.level,
                         barCount: 10,
                         idle: model.overlayPhase != .listening,
                         fixedBarWidth: 2.5,
                         spacing: 2,
                         minBarHeight: 5)
                .frame(width: 44, height: 24)

            liveText

            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                Text(model.overlayElapsedLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary.opacity(0.62))
            }
        }
        .padding(.leading, 15)
        .padding(.trailing, 16)
        .frame(width: model.overlayStyle.contentSize.width,
               height: model.overlayStyle.contentSize.height)
        .modifier(OverlaySurface(cornerRadius: model.overlayStyle.cornerRadius,
                                 restartToken: model.recordingStartedAt))
    }

    private var liveText: some View {
        let value = model.overlayLiveText
        return Text(value.isEmpty ? model.overlayPlaceholder : value)
            .font(.system(size: 14.5))
            .lineLimit(1)
            .truncationMode(.head)
            .foregroundStyle(value.isEmpty ? Color.primary.opacity(0.55) : Color.primary.opacity(0.94))
            .frame(maxWidth: .infinity, alignment: .leading)
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.05),
                    .init(color: .black, location: 1)
                ], startPoint: .leading, endPoint: .trailing)
            )
    }
}

// MARK: - 2 · Card

/// A small card that names the target app, so you can see where your words go.
private struct CardOverlay: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                TargetAppIcon(app: model.targetApp,
                              name: model.overlayTargetAppName)
                Text(model.overlayTargetAppName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .lineLimit(1)
                if model.activeProfile != .generic {
                    Text(model.activeProfile.label.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .kerning(0.4)
                        .foregroundStyle(Color.primary.opacity(0.55))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
                if model.isGenerateSession {
                    Text("GEN")
                        .font(.system(size: 9, weight: .semibold))
                        .kerning(0.4)
                        .foregroundStyle(OverlayPalette.accent.opacity(0.9))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(OverlayPalette.accent.opacity(0.12)))
                } else if model.isEditSession {
                    Text("EDIT")
                        .font(.system(size: 9, weight: .semibold))
                        .kerning(0.4)
                        .foregroundStyle(OverlayPalette.accent.opacity(0.9))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(OverlayPalette.accent.opacity(0.12)))
                }
                Spacer(minLength: 6)
                PulseDot(color: model.overlayDotColor,
                         active: model.overlayPhase == .listening,
                         size: 6)
                Text(model.overlayStateLabel)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.primary.opacity(0.62))
            }

            WaveformView(levels: model.overlayLevels,
                         level: model.previewLevel ?? model.level,
                         barCount: 30,
                         idle: model.overlayPhase != .listening,
                         fixedBarWidth: 3,
                         spacing: 2.5,
                         minBarHeight: 4)
                .frame(height: 24)
                .mask(
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.09),
                        .init(color: .black, location: 0.91),
                        .init(color: .clear, location: 1)
                    ], startPoint: .leading, endPoint: .trailing)
                )

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                liveText
                if model.overlayPhase == .listening { Caret() }
                Spacer(minLength: 4)
                TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                    Text(model.overlayElapsedLabel)
                        .font(.system(size: 11, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Color.primary.opacity(0.55))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: model.overlayStyle.contentSize.width,
               height: model.overlayStyle.contentSize.height)
        .modifier(OverlaySurface(cornerRadius: model.overlayStyle.cornerRadius,
                                 restartToken: model.recordingStartedAt))
    }

    private var liveText: some View {
        let value = model.overlayLiveText
        return Text(value.isEmpty ? model.overlayPlaceholder : value)
            .font(.system(size: 14))
            .lineLimit(1)
            .truncationMode(.head)
            .foregroundStyle(value.isEmpty ? Color.primary.opacity(0.55) : Color.primary.opacity(0.95))
    }
}

// MARK: - Small pieces

/// The target app's icon, shown so the overlay always says where the text lands.
private struct TargetAppIcon: View {
    var app: NSRunningApplication?
    var name: String
    var size: CGFloat = 18
    var isError: Bool = false

    private var cornerRadius: CGFloat { size * 0.25 }

    var body: some View {
        Group {
            if let icon = app?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.22))
                    .overlay(
                        Text(String(name.prefix(1)).uppercased())
                            .font(.system(size: size * 0.55, weight: .semibold))
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.red.opacity(isError ? 0.85 : 0), lineWidth: 1.5)
        )
        .accessibilityLabel(name)
    }
}

private struct PulseDot: View {
    var color: Color
    var active: Bool
    var size: CGFloat = 9

    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .stroke(color.opacity(0.5), lineWidth: 1)
                    .scaleEffect(pulse ? 2.0 : 1)
                    .opacity(pulse ? 0 : 0.85)
            )
            .onAppear(perform: restart)
            .onChange(of: active) { _, _ in restart() }
    }

    private func restart() {
        pulse = false
        guard active else { return }
        withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
            pulse = true
        }
    }
}

private struct Caret: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.53)) { context in
            let on = Int(context.date.timeIntervalSinceReferenceDate / 0.53) % 2 == 0
            RoundedRectangle(cornerRadius: 1)
                .fill(OverlayPalette.accent)
                .frame(width: 2, height: 15)
                .opacity(on ? 1 : 0)
        }
    }
}

// MARK: - Panel

/// Owns the floating `NSPanel`. Non-activating so focus never leaves the app
/// the user is typing into.
@MainActor
final class HUDController {
    private var panel: NSPanel?
    private weak var model: AppModel?
    private var builtStyle: AppModel.OverlayStyle?

    func show(model: AppModel) {
        self.model = model
        let style = model.overlayStyle
        let panel = panel ?? makePanel(model: model)
        self.panel = panel
        // The panel is sized to the overlay, so a style change needs a rebuild.
        if builtStyle != style {
            builtStyle = style
            resize(panel, model: model)
        }
        position(panel)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    // MARK: Panel plumbing

    private func panelSize(for style: AppModel.OverlayStyle) -> NSSize {
        let content = style.contentSize
        let bleed = HUDView.shadowBleed
        return NSSize(width: content.width + bleed * 2, height: content.height + bleed * 2)
    }

    private func resize(_ panel: NSPanel, model: AppModel) {
        panel.setContentSize(panelSize(for: model.overlayStyle))
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
    }

    private func makePanel(model: AppModel) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize(for: model.overlayStyle)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false          // the SwiftUI surface draws its own
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        // Aim the *visible* overlay 54pt above the bottom of the screen; the
        // panel carries shadowBleed of transparent margin below it.
        let origin = NSPoint(x: visible.midX - size.width / 2,
                             y: visible.minY + 54 - HUDView.shadowBleed)
        panel.setFrameOrigin(origin)
    }
}
