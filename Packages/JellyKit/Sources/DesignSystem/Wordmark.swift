import SwiftUI

/// Four-pointed spark, drawn as a path (no bitmap asset). Mockup viewBox 40×40.
public struct SparkShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 40
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit)
        }
        var path = Path()
        path.move(to: point(20, 1))
        path.addCurve(to: point(39, 20), control1: point(21.6, 11.6), control2: point(28.4, 18.4))
        path.addCurve(to: point(20, 39), control1: point(28.4, 21.6), control2: point(21.6, 28.4))
        path.addCurve(to: point(1, 20), control1: point(18.4, 28.4), control2: point(11.6, 21.6))
        path.addCurve(to: point(20, 1), control1: point(11.6, 18.4), control2: point(18.4, 11.6))
        path.closeSubpath()
        return path
    }
}

/// `jellyfuse` wordmark: spark + `jelly` in white + `fuse` in the brand gradient.
public struct Wordmark: View {
    @Environment(\.designMetrics) private var metrics
    public init() {}

    public var body: some View {
        HStack(spacing: Design.Spacing.s) {
            SparkShape()
                .fill(Design.Palette.accentGradient)
                .frame(width: metrics.wordmarkHeight, height: metrics.wordmarkHeight)
            HStack(spacing: 0) {
                Text("jelly").foregroundStyle(Design.Palette.textPrimary)
                Text("fuse").foregroundStyle(Design.Palette.accentGradient)
            }
            .font(.system(size: metrics.wordmarkHeight, weight: .heavy))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("jellyfuse")
    }
}

#if DEBUG
#Preview("Wordmark") {
    Wordmark()
        .padding(Design.Spacing.xl)
        .background(Design.Palette.canvas)
}
#endif
