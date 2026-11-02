import SwiftUI

/// Watch progress along the bottom edge of a card (mockup `.prog`).
struct ProgressBar: View {
    @Environment(\.designMetrics) private var metrics
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.28))
                Rectangle()
                    .fill(Design.Palette.accentGradient)
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: metrics.progressBarHeight)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Progress bar") {
    VStack(spacing: Design.Spacing.m) {
        ForEach([0.18, 0.62, 1.0], id: \.self) { value in
            ProgressBar(progress: value).frame(width: Design.Metrics.tv.landscape.width)
        }
    }
    .padding(Design.Metrics.tv.screenMargin)
    .background(Design.Palette.canvas)
}
#endif
