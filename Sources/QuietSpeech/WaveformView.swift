import SwiftUI

/// Scrolling bar visualiser driven by the live microphone level.
///
/// Two layout modes. Leave `fixedBarWidth` nil to spread `barCount` bars across
/// the whole frame (the in-window meter). Set it to draw a centred ribbon of
/// fixed-width bars at whatever natural size the caller gives the view — that is
/// what the overlay's compact meters use.
struct WaveformView: View {
    var levels: [Float]
    var level: Float
    var barCount: Int = 36
    var idle: Bool = false
    var fixedBarWidth: CGFloat? = nil
    var spacing: CGFloat = 2
    var minBarHeight: CGFloat = 2.5

    /// One accent, darker at the base.
    private let tip = SettingsColor.accent
    private let base = SettingsColor.accentPress

    var body: some View {
        Canvas { context, size in
            let count = max(1, barCount)
            let width = fixedBarWidth
                ?? max(1.5, (size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            let total = CGFloat(count) * width + spacing * CGFloat(count - 1)
            let startX = max(0, (size.width - total) / 2)
            let midY = size.height / 2

            // Left-pad so bars scroll in from the right.
            let tail = Array(levels.suffix(count))
            let padded = Array(repeating: Float(0), count: max(0, count - tail.count)) + tail

            for i in 0..<count {
                let value = CGFloat(min(1, max(0, padded[i])))
                let magnitude = idle ? 0.14 : max(0.14, value)
                let height = max(minBarHeight, magnitude * size.height)
                let x = startX + CGFloat(i) * (width + spacing)
                let rect = CGRect(x: x, y: midY - height / 2, width: width, height: height)
                let path = Path(roundedRect: rect, cornerRadius: width / 2)
                let opacity = idle ? 0.45 : 0.55 + 0.45 * value
                context.fill(path, with: .linearGradient(
                    Gradient(colors: [tip.opacity(opacity), base.opacity(opacity)]),
                    startPoint: CGPoint(x: x, y: rect.minY),
                    endPoint: CGPoint(x: x, y: rect.maxY)
                ))
            }
        }
        .animation(.linear(duration: 0.03), value: levels.count)
    }
}
