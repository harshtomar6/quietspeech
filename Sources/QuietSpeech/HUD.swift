import SwiftUI
import AppKit
import os

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
        // Sized from the screen's notch instead; see NotchLayout.
        case .notch:   return .zero
        case .capsule: return CGSize(width: 380, height: 54)
        case .card:    return CGSize(width: 360, height: 102)
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .notch:   return 10
        case .capsule: return 27
        // Concentric with the content inside, as macOS 26 glass shapes are.
        case .card:    return 22
        }
    }
}

// MARK: - Overlay-facing state

private extension AppModel {
    var overlayLevels: [Float] { previewLevels ?? levels }

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
    /// The notch of the screen the panel was built for. Only the notch style uses it.
    var notch: NotchMetrics = .fallback

    /// Room reserved around the overlay so the SwiftUI shadow isn't clipped by
    /// the borderless panel's bounds.
    static let shadowBleed: CGFloat = 30

    var body: some View {
        if model.overlayStyle == .notch {
            NotchOverlay(model: model,
                         notch: notch,
                         notice: model.isRecording ? nil : model.learningNotice)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            overlay
                .padding(Self.shadowBleed)
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if let notice = model.learningNotice, !model.isRecording {
            LearningNoticeOverlay(text: notice, style: model.overlayStyle)
        } else {
            switch model.overlayStyle {
            case .capsule: CapsuleOverlay(model: model)
            case .card, .notch: CardOverlay(model: model)
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

/// macOS 26 Liquid Glass, as the system's own floating indicators use. It
/// draws its own edge highlight and shadow, and adapts to light, dark,
/// Reduce Transparency and Increase Contrast.
private struct OverlaySurface: ViewModifier {
    let cornerRadius: CGFloat
    /// Re-plays the entrance animation whenever this changes (each new session).
    let restartToken: Date?

    @State private var shown = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .glassEffect(.regular, in: shape)
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

            StatusIndicator(model: model)

            liveText

            ElapsedLabel(model: model)
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
            .foregroundStyle(value.isEmpty ? .secondary : .primary)
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
                Text(cardTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                statusGlyph
                Text(model.overlayStateLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
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
                ElapsedLabel(model: model)
            }
        }
        .padding(.horizontal, 16)
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
            .foregroundStyle(value.isEmpty ? .secondary : .primary)
    }

    /// "Google Chrome · Email": where the words go, and how they'll be shaped.
    private var cardTitle: String {
        guard model.activeProfile != .generic else { return model.overlayTargetAppName }
        return "\(model.overlayTargetAppName) \u{00b7} \(model.activeProfile.label)"
    }

    /// The card's waveform already shows listening; the header shows the
    /// other states with a system spinner or symbol.
    @ViewBuilder
    private var statusGlyph: some View {
        switch model.overlayPhase {
        case .listening:
            EmptyView()
        case .processing:
            ProgressView().controlSize(.mini)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(OverlayPalette.success)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(OverlayPalette.warn)
        }
    }
}

// MARK: - 3 · Notch

/// Where the camera housing sits on a screen. Screens without a notch get a
/// zero width and the menu bar's height, so the island hangs from the middle
/// of the menu bar instead.
struct NotchMetrics: Equatable {
    var width: CGFloat
    var height: CGFloat

    var hasNotch: Bool { width > 0 }

    static let fallback = NotchMetrics(width: 0, height: 24)

    init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
    }

    @MainActor
    init(screen: NSScreen) {
        let top = screen.safeAreaInsets.top
        if top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            width = max(0, screen.frame.width - left.width - right.width)
            height = top
        } else {
            width = 0
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            height = menuBar > 4 ? menuBar : 24
        }
    }
}

/// The island's sizes, including the concave "ears" that blend it into the
/// top edge of the screen.
struct NotchLayout {
    static let ear: CGFloat = 8
    /// Room around the island for the blurred glow.
    static let glowBleed: CGFloat = 44
    /// Space on each side of the camera for the icon, timer or status.
    private static let wing: CGFloat = 112
    /// Height of the transcript line below the notch.
    static let textRow: CGFloat = 44

    let notch: NotchMetrics

    /// The same size as the notch, so the island grows out of it.
    var collapsed: CGSize {
        CGSize(width: max(notch.width, 120) + Self.ear * 2, height: notch.height)
    }

    /// Listening and processing: wings beside the camera and a line of text.
    var expanded: CGSize {
        CGSize(width: max(notch.width + Self.wing * 2, 420) + Self.ear * 2,
               height: notch.height + Self.textRow)
    }

    /// Done and error: one slim strip level with the notch.
    var compact: CGSize {
        CGSize(width: max(notch.width + Self.wing * 2, 260) + Self.ear * 2,
               height: notch.height)
    }

    var panelSize: NSSize {
        NSSize(width: expanded.width + Self.glowBleed * 2,
               height: expanded.height + Self.glowBleed)
    }
}

/// Black island with a flat top, concave ears at the top corners and rounded
/// bottom corners, like the notch itself.
struct NotchIslandShape: Shape {
    var bottomRadius: CGFloat
    var earRadius: CGFloat = NotchLayout.ear

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let e = max(0, min(earRadius, rect.width / 4, rect.height))
        let r = max(0, min(bottomRadius, (rect.width - e * 2) / 2, rect.height - e))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + e, y: rect.minY + e),
                       control: CGPoint(x: rect.minX + e, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + e, y: rect.maxY - r))
        p.addArc(tangent1End: CGPoint(x: rect.minX + e, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.minX + e + r, y: rect.maxY),
                 radius: r)
        p.addLine(to: CGPoint(x: rect.maxX - e - r, y: rect.maxY))
        p.addArc(tangent1End: CGPoint(x: rect.maxX - e, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.maxX - e, y: rect.maxY - r),
                 radius: r)
        p.addLine(to: CGPoint(x: rect.maxX - e, y: rect.minY + e))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - e, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// The Siri-like colors of the rim, in order around the island.
enum HaloPalette {
    static let colors: [Color] = [
        Color(red: 1.00, green: 0.31, blue: 0.64),
        Color(red: 0.54, green: 0.36, blue: 1.00),
        Color(red: 0.25, green: 0.66, blue: 1.00),
        Color(red: 0.28, green: 0.90, blue: 0.78),
        Color(red: 1.00, green: 0.71, blue: 0.28),
        Color(red: 1.00, green: 0.31, blue: 0.64)
    ]
}

/// Grows out of the notch while you dictate: the app icon and timer sit
/// beside the camera, the transcript runs underneath, and a rotating colored
/// rim glows brighter as you speak.
private struct NotchOverlay: View {
    let model: AppModel
    let notch: NotchMetrics
    var notice: String?

    @State private var open = false

    private var layout: NotchLayout { NotchLayout(notch: notch) }

    private enum Mode { case live, compact, notice }

    private var mode: Mode {
        if notice != nil { return .notice }
        switch model.overlayPhase {
        case .listening, .processing: return .live
        case .done, .error: return .compact
        }
    }

    private var size: CGSize {
        guard open else { return layout.collapsed }
        return mode == .compact ? layout.compact : layout.expanded
    }

    private var radius: CGFloat { open && mode != .compact ? 22 : 10 }

    private var showsRim: Bool { open && mode == .live }

    private var level: CGFloat {
        CGFloat(min(max(model.previewLevel ?? model.level, 0), 1))
    }

    var body: some View {
        let shape = NotchIslandShape(bottomRadius: radius)
        ZStack(alignment: .top) {
            HaloRim(radius: radius,
                    level: model.overlayPhase == .listening ? level : 0,
                    fast: model.overlayPhase == .processing,
                    active: showsRim)
                .opacity(showsRim ? 1 : 0)
            shape.fill(Color.black)
            content
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)
        }
        .frame(width: size.width, height: size.height)
        // Without a notch there is nothing to grow out of, so fade in too.
        .opacity(open || notch.hasNotch ? 1 : 0)
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: size)
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: radius)
        .animation(.easeOut(duration: 0.3), value: showsRim)
        .animation(.easeOut(duration: 0.15), value: level)
        .environment(\.colorScheme, .dark)
        .onAppear { play() }
        .onChange(of: model.recordingStartedAt) { _, _ in play() }
    }

    private func play() {
        open = false
        DispatchQueue.main.async { open = true }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leading.frame(maxWidth: .infinity, alignment: .leading)
                // The camera housing.
                Color.clear.frame(width: notch.width)
                trailing.frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: notch.height)

            if mode != .compact {
                liveText
                    .frame(height: NotchLayout.textRow - 6)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, NotchLayout.ear + 14)
        .opacity(open ? 1 : 0)
        .animation(.easeOut(duration: 0.22).delay(open ? 0.1 : 0), value: open)
        .animation(.snappy(duration: 0.2), value: model.overlayPhase)
    }

    @ViewBuilder
    private var leading: some View {
        if notice != nil {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HaloPalette.colors[1])
        } else {
            switch model.overlayPhase {
            case .listening, .processing:
                TargetAppIcon(app: model.targetApp,
                              name: model.overlayTargetAppName,
                              size: 16)
            case .done:
                status(symbol: "checkmark.circle.fill",
                       tint: OverlayPalette.success,
                       text: model.overlayStateLabel)
                    .transition(.symbolEffect(.drawOn))
            case .error:
                status(symbol: "exclamationmark.triangle.fill",
                       tint: OverlayPalette.warn,
                       text: model.overlayPlaceholder)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if notice != nil {
            EmptyView()
        } else {
            switch model.overlayPhase {
            case .listening:
                ElapsedLabel(model: model)
            case .processing:
                ProgressView().controlSize(.mini)
            case .done, .error:
                TargetAppIcon(app: model.targetApp,
                              name: model.overlayTargetAppName,
                              size: 16,
                              isError: model.overlayPhase == .error)
            }
        }
    }

    private func status(symbol: String, tint: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var liveText: some View {
        let value = notice ?? model.overlayLiveText
        return Text(value.isEmpty ? model.overlayPlaceholder : value)
            .font(.system(size: 14))
            .lineLimit(1)
            .truncationMode(.head)
            .foregroundStyle(.white.opacity(value.isEmpty ? 0.5 : 0.95))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.05),
                    .init(color: .black, location: 1)
                ], startPoint: .leading, endPoint: .trailing)
            )
    }
}

/// The rotating colored edge behind the island: a crisp rim plus a blurred
/// copy whose glow follows the voice level. Spins faster while processing.
private struct HaloRim: View {
    let radius: CGFloat
    let level: CGFloat
    let fast: Bool
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let degrees = reduceMotion ? 0 : (t * (fast ? 300 : 80)).truncatingRemainder(dividingBy: 360)
            let gradient = AngularGradient(colors: HaloPalette.colors,
                                           center: .center,
                                           angle: .degrees(degrees))
            ZStack(alignment: .top) {
                NotchIslandShape(bottomRadius: radius + 8)
                    .fill(gradient)
                    .padding(.horizontal, -8)
                    .padding(.bottom, -8)
                    .blur(radius: 9 + 12 * level)
                    .opacity(0.4 + 0.6 * level)
                NotchIslandShape(bottomRadius: radius + 1.5)
                    .fill(gradient)
                    .padding(.horizontal, -1.5)
                    .padding(.bottom, -1.5)
            }
        }
    }
}

/// Small still of the notch overlay for the Settings and onboarding pickers.
struct NotchOverlayThumbnail: View {
    var text = "Meeting at three."
    /// Drawn at 150×36 and scaled, so layout takes only the scaled size.
    var scale: CGFloat = 1

    var body: some View {
        island
            .scaleEffect(scale, anchor: .top)
            .frame(width: 150 * scale, height: 36 * scale, alignment: .top)
    }

    @ViewBuilder private var island: some View {
        let shape = NotchIslandShape(bottomRadius: 12, earRadius: 5)
        let gradient = AngularGradient(colors: HaloPalette.colors, center: .center, angle: .degrees(40))
        ZStack(alignment: .top) {
            shape.fill(gradient)
                .padding(.horizontal, -5)
                .padding(.bottom, -5)
                .blur(radius: 6)
                .opacity(0.75)
            shape.fill(gradient)
                .padding(.horizontal, -1)
                .padding(.bottom, -1)
            shape.fill(Color.black)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(SettingsColor.accent)
                        .frame(width: 9, height: 9)
                    Spacer()
                    Text("0:04")
                        .font(.system(size: 7.5))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(height: 13)
                Text(text)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
        }
        .frame(width: 150, height: 36)
    }
}

// MARK: - Small pieces

/// What the session is doing, in one place: the live waveform while
/// listening, then a system spinner, a checkmark or a warning.
private struct StatusIndicator: View {
    let model: AppModel
    var barCount = 10
    var width: CGFloat = 44

    var body: some View {
        ZStack {
            switch model.overlayPhase {
            case .listening:
                WaveformView(levels: model.overlayLevels,
                             level: model.previewLevel ?? model.level,
                             barCount: barCount,
                             idle: false,
                             fixedBarWidth: 2.5,
                             spacing: 2,
                             minBarHeight: 5)
                    .frame(width: width, height: 24)
                    .transition(.opacity)
            case .processing:
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(OverlayPalette.success)
                    .transition(.symbolEffect(.drawOn))
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(OverlayPalette.warn)
                    .transition(.symbolEffect(.appear))
            }
        }
        .frame(width: width, height: 24)
        .animation(.snappy(duration: 0.2), value: model.overlayPhase)
    }
}

/// The session timer, in the system font with fixed-width digits like the
/// screen-recording timer in the menu bar.
private struct ElapsedLabel: View {
    let model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            Text(model.overlayElapsedLabel)
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

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
    /// What the panel's size and content were built for.
    private struct BuiltLayout: Equatable {
        var style: AppModel.OverlayStyle
        var notch: NotchMetrics
    }
    private var built: BuiltLayout?
    private let log = Logger(subsystem: "dev.harsh.quietspeech", category: "overlay")

    func show(model: AppModel) {
        self.model = model
        let screen = NSScreen.main ?? NSScreen.screens.first
        let layout = BuiltLayout(style: model.overlayStyle,
                                 notch: screen.map { NotchMetrics(screen: $0) } ?? .fallback)
        let panel = panel ?? makePanel(model: model, notch: layout.notch)
        self.panel = panel
        // The panel is sized to the overlay (and, for the notch style, to the
        // screen's notch), so either changing needs a rebuild.
        if built != layout {
            built = layout
            resize(panel, model: model, notch: layout.notch)
        }
        if let screen { position(panel, on: screen, style: layout.style) }

        present(panel)
    }

    func present(_ panel: NSPanel) {
        self.panel = panel
        // SwiftUI animates the content's entrance. Keep window visibility
        // synchronous: an earlier fade-out completion must never order out
        // the same panel after another dictation has shown it again.
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        log.info("show window=\(panel.windowNumber) visible=\(panel.isVisible) activeSpace=\(panel.isOnActiveSpace)")
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        log.info("hide window=\(panel.windowNumber)")
    }

    // MARK: Panel plumbing

    private func panelSize(for style: AppModel.OverlayStyle, notch: NotchMetrics) -> NSSize {
        if style == .notch { return NotchLayout(notch: notch).panelSize }
        let content = style.contentSize
        let bleed = HUDView.shadowBleed
        return NSSize(width: content.width + bleed * 2, height: content.height + bleed * 2)
    }

    private func resize(_ panel: NSPanel, model: AppModel, notch: NotchMetrics) {
        panel.setContentSize(panelSize(for: model.overlayStyle, notch: notch))
        panel.contentView = NSHostingView(rootView: HUDView(model: model, notch: notch))
    }

    private func makePanel(model: AppModel, notch: NotchMetrics) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize(for: model.overlayStyle, notch: notch)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: HUDView(model: model, notch: notch))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false          // the SwiftUI surface draws its own
        // Above the menu bar, so the notch style can cover it.
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = true
        // Floating overlays must join the focused app's set as well as its
        // Space; canJoinAllSpaces alone can leave them off-screen in native
        // document apps and full-screen workspaces.
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    private func position(_ panel: NSPanel, on screen: NSScreen, style: AppModel.OverlayStyle) {
        let size = panel.frame.size
        if style == .notch {
            // Flush with the top edge, centred on the camera housing.
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2,
                                         y: screen.frame.maxY - size.height))
            return
        }
        let visible = screen.visibleFrame
        // Aim the *visible* overlay 54pt above the bottom of the screen; the
        // panel carries shadowBleed of transparent margin below it.
        let origin = NSPoint(x: visible.midX - size.width / 2,
                             y: visible.minY + 54 - HUDView.shadowBleed)
        panel.setFrameOrigin(origin)
    }
}
