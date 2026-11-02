import DesignSystem
import SwiftUI

/// Pure poster grid of a library (« Voir tout »). Props in, callbacks out.
struct RecentGridView: View {
    @Environment(\.designMetrics) private var metrics
    let title: String
    let items: [PosterModel]
    let isLoading: Bool
    let failureMessage: String?
    let onOpen: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.focusInset) {
                Text(title)
                    .font(Design.Typography.title)
                    .foregroundStyle(Design.Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let failureMessage {
                    Text(failureMessage)
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Palette.textSecondary)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: metrics.gridRowGap) {
                        if isLoading {
                            ForEach(0..<12, id: \.self) { _ in Skeleton(.poster) }
                        } else {
                            ForEach(items) { model in
                                PosterCard(model) { onOpen(model.detailId) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, metrics.screenMargin)
            .padding(.vertical, metrics.safeVertical)
        }
        .scrollClipDisabled()
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: metrics.poster.width), spacing: metrics.shelfGap, alignment: .top)]
    }
}
