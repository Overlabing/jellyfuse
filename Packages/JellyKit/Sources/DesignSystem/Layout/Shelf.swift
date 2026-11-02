import SwiftUI

/// Horizontal titled row of cards. Its own focus section; the next card peeks at the edge.
public struct Shelf<Item: Identifiable, Card: View>: View {
    @Environment(\.designMetrics) private var metrics
    private let title: String
    private let items: [Item]
    private let card: (Item) -> Card

    public init(title: String, items: [Item], @ViewBuilder card: @escaping (Item) -> Card) {
        self.title = title
        self.items = items
        self.card = card
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Design.Typography.sectionTitle)
                .foregroundStyle(Design.Palette.textPrimary)
                .padding(.leading, metrics.screenMargin)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: metrics.shelfGap) {
                    ForEach(items) { card($0) }
                }
                .padding(.horizontal, metrics.screenMargin)
                .padding(.vertical, metrics.focusInset)
            }
            .scrollClipDisabled()
        }
        .focusBlock()
    }
}

#if DEBUG
#Preview("Shelf – posters and landscapes") {
    PreviewFocusScope { namespace in
        VStack(alignment: .leading, spacing: 0) {
            Shelf(title: "À suivre", items: PreviewData.landscapes) { model in
                LandscapeCard(model) {}
                    .previewDefaultFocus(model.id == PreviewData.landscapes[0].id, in: namespace)
            }
            Shelf(title: "Récents", items: PreviewData.posters) { model in
                PosterCard(model) {}
            }
        }
    }
}
#endif
