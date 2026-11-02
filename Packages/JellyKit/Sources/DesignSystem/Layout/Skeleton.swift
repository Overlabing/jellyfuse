import SwiftUI

/// Static placeholder with the final shape of a card (no spinner, no shimmer).
public struct Skeleton: View {
    public enum Kind: Sendable {
        case poster
        case landscape

        func size(in metrics: Design.Metrics) -> CGSize {
            switch self {
            case .poster: metrics.poster
            case .landscape: metrics.landscape
            }
        }
    }

    private let kind: Kind
    @Environment(\.designMetrics) private var metrics

    public init(_ kind: Kind) {
        self.kind = kind
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: Design.Radius.card)
            .fill(Design.Palette.surface)
            .frame(width: kind.size(in: metrics).width, height: kind.size(in: metrics).height)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Skeleton") {
    HStack(spacing: Design.Metrics.tv.shelfGap) {
        Skeleton(.poster)
        Skeleton(.poster)
        Skeleton(.landscape)
        Skeleton(.landscape)
    }
    .padding(Design.Metrics.tv.screenMargin)
    .background(Design.Palette.canvas)
}
#endif
