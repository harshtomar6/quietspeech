import SwiftUI

/// Shared surface styling for the setup window and the settings form.
enum Theme {
    static let corner: CGFloat = 14
    static let padding: CGFloat = 16
}

/// A soft raised block. `selected` tints and outlines it for pickable cards.
struct Card<Content: View>: View {
    var selected: Bool
    var content: Content

    init(selected: Bool = false, @ViewBuilder content: () -> Content) {
        self.selected = selected
        self.content = content()
    }

    var body: some View {
        content
            .padding(Theme.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.09),
                                  lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}

/// Rounded-square glyph that anchors each step.
struct IconTile: View {
    let symbol: String
    var tint: Color = .accentColor
    var size: CGFloat = 46

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(tint.opacity(0.14))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }
}

// MARK: - Settings

/// Card that holds a group of rows. Rows supply their own vertical padding.
struct SectionCard<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, Theme.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
            )
    }
}

/// One labelled row with a control on the trailing edge.
struct SettingRow<Control: View>: View {
    let title: String
    var subtitle: String?
    let control: Control

    init(_ title: String, subtitle: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 10)
            control
        }
        .padding(.vertical, 11)
    }
}

struct RowDivider: View {
    var body: some View {
        Divider().opacity(0.55)
    }
}

/// Explanatory caption that sits under a section card.
struct SettingNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 3)
    }
}

