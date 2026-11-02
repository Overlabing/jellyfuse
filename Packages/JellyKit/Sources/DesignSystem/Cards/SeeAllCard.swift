import SwiftUI

/// « Voir tout » card closing a shelf: poster-sized, surface fill, centered label.
public struct SeeAllCard: View {
    @Environment(\.designMetrics) private var metrics
    private let onSelect: () -> Void

    public init(onSelect: @escaping () -> Void) {
        self.onSelect = onSelect
    }

    public var body: some View {
        Button(action: onSelect) {
            SeeAllFace()
                .frame(width: metrics.poster.width, height: metrics.poster.height)
        }
        .cardButtonStyle()
        .accessibilityLabel(String(localized: "Voir tout"))
    }
}

private struct SeeAllFace: View {
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(spacing: Design.Spacing.s) {
            Image(systemName: "arrow.right")
                .font(Design.Typography.title)
            Text("Voir tout")
                .font(Design.Typography.body.weight(.semibold))
        }
        .foregroundStyle(isFocused ? Design.Palette.textPrimary : Design.Palette.textSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Palette.surface, in: RoundedRectangle(cornerRadius: Design.Radius.card))
    }
}

#if DEBUG
#Preview("SeeAllCard") {
    PreviewFocusScope { namespace in
        HStack(alignment: .top, spacing: Design.Metrics.tv.shelfGap) {
            PosterCard(PreviewData.posters[0]) {}
            SeeAllCard {}.previewDefaultFocus(in: namespace)
        }
    }
}
#endif
