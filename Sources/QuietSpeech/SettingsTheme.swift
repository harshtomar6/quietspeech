import SwiftUI
import AppKit

// MARK: - Palette

enum SettingsColor {
    static let accent = dynamic(
        light: NSColor(srgbRed: 0.055, green: 0.561, blue: 0.639, alpha: 1),
        dark: NSColor(srgbRed: 0.361, green: 0.882, blue: 0.902, alpha: 1)
    )
    static let accentSoft = accent.opacity(0.11)
    static let accentSofter = accent.opacity(0.055)
    static let accentRing = accent.opacity(0.22)
    /// Solid fill for primary controls and the selected sidebar row.
    static let accentFill = dynamic(
        light: NSColor(srgbRed: 0.043, green: 0.498, blue: 0.573, alpha: 1),
        dark: NSColor(srgbRed: 0.361, green: 0.882, blue: 0.902, alpha: 1)
    )
    static let accentPress = dynamic(
        light: NSColor(srgbRed: 0.035, green: 0.424, blue: 0.490, alpha: 1),
        dark: NSColor(srgbRed: 0.271, green: 0.788, blue: 0.812, alpha: 1)
    )
    static let overlayBorder = dynamic(
        light: NSColor.white.withAlphaComponent(0.62),
        dark: NSColor.white.withAlphaComponent(0.12)
    )
    static let onAccent = dynamic(
        light: .white,
        dark: NSColor(srgbRed: 0.020, green: 0.165, blue: 0.200, alpha: 1)
    )
    static let sidebarSelected = dynamic(
        light: NSColor(srgbRed: 0.043, green: 0.498, blue: 0.573, alpha: 1),
        dark: NSColor(srgbRed: 0.047, green: 0.227, blue: 0.275, alpha: 1)
    )
    static let sidebarSelectedText = dynamic(
        light: .white,
        dark: .white
    )

    static let window = dynamic(
        light: NSColor(srgbRed: 0.969, green: 0.973, blue: 0.984, alpha: 1),
        dark: NSColor(srgbRed: 0.039, green: 0.078, blue: 0.106, alpha: 1)
    )
    static let sidebar = dynamic(
        light: NSColor(srgbRed: 0.957, green: 0.961, blue: 0.973, alpha: 1),
        dark: NSColor(srgbRed: 0.043, green: 0.094, blue: 0.125, alpha: 1)
    )
    static let card = dynamic(
        light: .white,
        dark: NSColor(srgbRed: 0.071, green: 0.122, blue: 0.153, alpha: 1)
    )
    static let cardMuted = dynamic(
        light: NSColor(srgbRed: 0.969, green: 0.973, blue: 0.980, alpha: 1),
        dark: NSColor(srgbRed: 0.090, green: 0.149, blue: 0.188, alpha: 1)
    )
    static let field = dynamic(
        light: .white,
        dark: NSColor(srgbRed: 0.047, green: 0.094, blue: 0.122, alpha: 1)
    )
    static let segmentTrack = dynamic(
        light: NSColor.black.withAlphaComponent(0.065),
        dark: NSColor.white.withAlphaComponent(0.08)
    )
    static let border = dynamic(
        light: NSColor.black.withAlphaComponent(0.08),
        dark: NSColor.white.withAlphaComponent(0.08)
    )
    static let borderStrong = dynamic(
        light: NSColor.black.withAlphaComponent(0.13),
        dark: NSColor.white.withAlphaComponent(0.14)
    )
    static let faintText = dynamic(
        light: NSColor(srgbRed: 0.545, green: 0.576, blue: 0.631, alpha: 1),
        dark: NSColor(srgbRed: 0.475, green: 0.510, blue: 0.561, alpha: 1)
    )
    static let green = dynamic(
        light: NSColor(srgbRed: 0.082, green: 0.612, blue: 0.388, alpha: 1),
        dark: NSColor(srgbRed: 0.239, green: 0.863, blue: 0.580, alpha: 1)
    )
    static let amber = dynamic(
        light: NSColor(srgbRed: 0.812, green: 0.518, blue: 0.063, alpha: 1),
        dark: NSColor(srgbRed: 0.878, green: 0.651, blue: 0.227, alpha: 1)
    )
    static let red = dynamic(
        light: NSColor(srgbRed: 0.851, green: 0.275, blue: 0.247, alpha: 1),
        dark: NSColor(srgbRed: 1.0, green: 0.420, blue: 0.384, alpha: 1)
    )
    static let blue = dynamic(
        light: NSColor(srgbRed: 0.231, green: 0.498, blue: 0.965, alpha: 1),
        dark: NSColor(srgbRed: 0.420, green: 0.620, blue: 1.0, alpha: 1)
    )
    static let violet = dynamic(
        light: NSColor(srgbRed: 0.545, green: 0.361, blue: 0.965, alpha: 1),
        dark: NSColor(srgbRed: 0.647, green: 0.494, blue: 0.980, alpha: 1)
    )

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
            case .darkAqua: return dark
            default: return light
            }
        })
    }
}

// MARK: - Surfaces

struct SettingsCard<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SettingsColor.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(SettingsColor.border, lineWidth: 1)
            )
    }
}

struct SettingsGroup<Content: View>: View {
    let label: String
    let icon: String
    var note: String?
    var content: Content

    init(_ label: String, icon: String, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.icon = icon
        self.note = note
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            SettingsCard { content }

            if let note {
                SettingsNote(note)
            }
        }
    }
}

struct SettingsPaneHeader: View {
    let title: String
    let subtitle: String
    var pill: SettingsStatusPill?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if let pill { pill }
        }
        .padding(.top, 2)
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var leading: AnyView?
    var trailing: Trailing

    init(_ title: String, subtitle: String? = nil, trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.leading = nil
        self.trailing = trailing()
    }

    init<Leading: View>(_ title: String, subtitle: String? = nil,
                        @ViewBuilder leading: () -> Leading,
                        @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.leading = AnyView(leading())
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 11) {
            if let leading { leading }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 10)
            trailing
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(SettingsColor.border)
            .frame(height: 1)
    }
}

struct SettingsNote: View {
    let text: String
    var icon = "info.circle"

    init(_ text: String, icon: String = "info.circle") {
        self.text = text
        self.icon = icon
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 10.5))
            Text(text)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.tertiary)
        .padding(.leading, 2)
    }
}

// MARK: - Pills and badges

struct SettingsStatusPill: View {
    enum Tone { case green, amber, accent, neutral }

    let text: String
    var tone: Tone = .neutral

    private var color: Color {
        switch tone {
        case .green: return SettingsColor.green
        case .amber: return SettingsColor.amber
        case .accent: return SettingsColor.accent
        case .neutral: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
        }
        .foregroundStyle(color)
        .focusable(false)
    }
}

struct SettingsCountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(SettingsColor.accent)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(Capsule().fill(SettingsColor.accentSoft))
    }
}

struct SettingsIconTile: View {
    let symbol: String
    var tint: Color = SettingsColor.accent
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(tint.opacity(0.12))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }
}

// MARK: - Controls

struct SettingsToggle: View {
    @Binding var isOn: Bool
    var onChange: (Bool) -> Void = { _ in }

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(SettingsColor.accent)
            .onChange(of: isOn) { _, value in onChange(value) }
    }
}

struct SettingsSegmentedControl<Option: Hashable>: View {
    let options: [(Option, String)]
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 1) {
            ForEach(options, id: \.0) { option in
                Button {
                    selection = option.0
                } label: {
                    Text(option.1)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(selection == option.0 ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background {
                            if selection == option.0 {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(SettingsColor.card)
                                    .shadow(color: .black.opacity(0.14), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.0 ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SettingsColor.segmentTrack)
        )
    }
}

struct SettingsField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var width: CGFloat?

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 12))
        .padding(.horizontal, 9)
        .frame(height: 27)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(SettingsColor.field)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(SettingsColor.borderStrong, lineWidth: 1)
        )
    }
}

// MARK: - Small pieces

struct SettingsHintButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(SettingsColor.accent)
        }
        .buttonStyle(.plain)
    }
}

struct SettingsEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}

/// Wrapping chip layout used for vocabulary.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Overlay preview

struct SettingsOverlayThumbnail: View {
    let style: AppModel.OverlayStyle

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.039, green: 0.078, blue: 0.106),
                                 Color(red: 0.020, green: 0.055, blue: 0.075)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )

            switch style {
            case .capsule:
                HStack(spacing: 6) {
                    HStack(alignment: .center, spacing: 1.5) {
                        ForEach([4, 8, 12, 7, 10, 5], id: \.self) { height in
                            Capsule()
                                .fill(SettingsColor.accent)
                                .frame(width: 2, height: CGFloat(height))
                        }
                    }
                    Text("Meeting at three.")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(Color.white.opacity(0.10)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            case .card:
                VStack(alignment: .leading, spacing: 3) {
                    Text("SLACK \u{00b7} LISTENING")
                        .font(.system(size: 6.5, weight: .semibold))
                        .kerning(0.4)
                        .foregroundStyle(.white.opacity(0.45))
                    Text("Meeting at three, then the roadmap.")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.075)))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .padding(.horizontal, 18)
            }
        }
        .frame(height: 92)
    }
}

// MARK: - Helpers

enum SettingsAppMonogram {
    static func initial(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first.map { String($0).uppercased() } ?? "?"
    }

    static func tint(_ name: String) -> Color {
        let lower = name.lowercased()
        if lower.contains("slack") { return Color(red: 0.36, green: 0.18, blue: 0.35) }
        if lower.contains("notion") { return Color(red: 0.10, green: 0.10, blue: 0.11) }
        if lower.contains("mail") { return SettingsColor.blue }
        if lower.contains("messages") { return SettingsColor.green }
        if lower.contains("cursor") { return Color(red: 0.15, green: 0.15, blue: 0.17) }
        if lower.contains("xcode") { return Color(red: 0.10, green: 0.43, blue: 0.94) }
        if lower.contains("terminal") { return Color(red: 0.20, green: 0.22, blue: 0.25) }
        if lower.contains("notes") { return SettingsColor.amber }
        if lower.contains("discord") { return Color(red: 0.35, green: 0.39, blue: 0.94) }
        let palette: [Color] = [SettingsColor.accent, SettingsColor.blue,
                                SettingsColor.violet, SettingsColor.amber,
                                Color(red: 0.84, green: 0.32, blue: 0.45)]
        let index = abs(name.hashValue) % palette.count
        return palette[index]
    }
}

extension Color {
    static var settingsAccent: Color { SettingsColor.accent }
}
