import SwiftUI

/// Round portrait with name and role underneath (detail-movie.html « Distribution »). The portrait is the
/// button (it opens the person's screen); the caption stays outside the label, as on the poster cards.
public struct CastCard: View {
    @Environment(\.designMetrics) private var metrics
    private let model: PersonModel
    private let onSelect: () -> Void

    public init(_ model: PersonModel, onSelect: @escaping () -> Void) {
        self.model = model
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: Design.Spacing.s) {
            Button(action: onSelect) {
                Artwork(model.image)
                    .frame(width: metrics.castPortrait, height: metrics.castPortrait)
                    .clipShape(Circle())
            }
            .roundButtonStyle()
            .accessibilityLabel(model.accessibilityDescription)
            VStack(spacing: Design.Spacing.xs) {
                Text(model.name)
                    .font(Design.Typography.caption.weight(.semibold))
                    .foregroundStyle(Design.Palette.textPrimary)
                    .lineLimit(1)
                if let role = model.role {
                    Text(role)
                        .font(Design.Typography.caption2)
                        .foregroundStyle(Design.Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityHidden(true)
        }
        .frame(width: metrics.castCardWidth)
    }
}

#if DEBUG
#Preview("CastCard – normal / focus") {
    PreviewFocusScope { namespace in
        HStack(alignment: .top, spacing: Design.Metrics.tv.shelfGap) {
            CastCard(PreviewData.people[0]) {}
            CastCard(PreviewData.people[1]) {}.previewDefaultFocus(in: namespace)
            CastCard(PreviewData.people[2]) {}
        }
    }
}
#endif
