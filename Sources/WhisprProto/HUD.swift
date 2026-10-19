import SwiftUI
import AppKit

// MARK: - Palette

private enum OverlayPalette {
    static let accent = Color(red: 0.196, green: 0.843, blue: 0.294)       // #32d74b
    static let warn = Color(red: 1.000, green: 0.624, blue: 0.039)         // #ff9f0a
}

extension AppModel.OverlayStyle {
    /// Size of the visible overlay. The panel is larger by the shadow bleed.
    var contentSize: CGSize {
        switch self {
        case .capsule: return CGSize(width: 440, height: 54)
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
        case .listening, .done: return OverlayPalette.accent
        case .error: return .red
        }
    }

    var overlayStateLabel: String {
        switch overlayPhase {
        case .listening: return "Listening"
        case .done: return autoInsert ? "Inserted" : "Ready"
        case .error: return "Error"
        }
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
        case .listening: return "Speak now…"
        case .done: return "Done"
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
        switch model.overlayStyle {
        case .capsule: CapsuleOverlay(model: model)
        case .card:    CardOverlay(model: model)
        }
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
            .overlay(shape.strokeBorder(.white.opacity(0.11), lineWidth: 1))
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

/// One slim line: pulse dot, level meter, live text, timer.
private struct CapsuleOverlay: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 11) {
            PulseDot(color: model.overlayDotColor,
                     active: model.overlayPhase == .listening)

            WaveformView(levels: model.overlayLevels,
                         level: model.previewLevel ?? model.level,
                         barCount: 14,
                         idle: model.overlayPhase != .listening,
                         fixedBarWidth: 2.5,
                         spacing: 2.5,
                         minBarHeight: 5)
                .frame(width: 68, height: 24)

            liveText

            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                Text(model.overlayElapsedLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
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
            .foregroundStyle(value.isEmpty ? Color.secondary : Color.primary.opacity(0.94))
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
                appIcon
                Text(appName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                PulseDot(color: model.overlayDotColor,
                         active: model.overlayPhase == .listening,
                         size: 6)
                Text(model.overlayStateLabel)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
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
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: model.overlayStyle.contentSize.width,
               height: model.overlayStyle.contentSize.height)
        .modifier(OverlaySurface(cornerRadius: model.overlayStyle.cornerRadius,
                                 restartToken: model.recordingStartedAt))
    }

    private var appName: String {
        model.targetApp?.localizedName ?? "Frontmost app"
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = model.targetApp?.icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .fill(Color.secondary.opacity(0.22))
                .frame(width: 18, height: 18)
                .overlay(
                    Text(String(appName.prefix(1)).uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                )
        }
    }

    private var liveText: some View {
        let value = model.overlayLiveText
        return Text(value.isEmpty ? model.overlayPlaceholder : value)
            .font(.system(size: 14))
            .lineLimit(1)
            .truncationMode(.head)
            .foregroundStyle(value.isEmpty ? Color.secondary : Color.primary.opacity(0.95))
    }
}

// MARK: - Small pieces

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
