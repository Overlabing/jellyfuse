import SwiftUI

/// Round portrait with name and role underneath (detail-movie.html « Distribution »). Not a button:
/// there is no person screen yet, but the card is focusable so the remote can scroll down to the row.
public struct CastCard: View {
    @Environment(\.designMetrics) private var metrics
    private let model: PersonModel

    public init(_ model: PersonModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: Design.Spacing.s) {
            CastPortrait(source: model.image, diameter: metrics.castPortrait)
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
        }
        .frame(width: metrics.castCardWidth)
        .focusable()
        .focusEffectDisabled()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityDescription)
    }
}

/// The portrait lifts when the card is focused (the card itself is the focusable view).
private struct CastPortrait: View {
    let source: ArtworkSource
    let diameter: CGFloat
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Artwork(source)
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .scaleEffect(isFocused ? Design.Focus.scale : 1)
            .shadow(
                color: .black.opacity(isFocused ? Design.Focus.shadowOpacity : 0),
                radius: Design.Focus.shadowRadius, y: Design.Focus.shadowOffsetY
            )
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

#if DEBUG
#Preview("CastCard – normal / focus") {
    PreviewFocusScope { namespace in
        HStack(alignment: .top, spacing: Design.Metrics.tv.shelfGap) {
            CastCard(PreviewData.people[0])
            CastCard(PreviewData.people[1]).previewDefaultFocus(in: namespace)
            CastCard(PreviewData.people[2])
        }
    }
}
#endif
