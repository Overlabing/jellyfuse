import DesignSystem
import HomePresentation
import SwiftUI

/// The poster grid proper: skeletons while the first page loads, a message on failure or emptiness, the
/// loaded posters, and a footer for the next page. Shared by the library tab, « Voir tout », collections
/// and people. Props in, callbacks out.
struct PosterGrid: View {
    @Environment(\.designMetrics) private var metrics
    let content: PosterGridContent
    let isLoading: Bool
    let failureMessage: String?
    let emptyMessage: String
    let isLoadingMore: Bool
    let loadMoreFailed: Bool
    let onOpen: (String) -> Void
    /// A poster near the end of what is loaded became visible.
    let onLoadMore: () -> Void

    var body: some View {
        if let failureMessage, content.isEmpty {
            message(failureMessage)
        } else if isLoading, content.isEmpty {
            LazyVGrid(columns: columns, alignment: .leading, spacing: metrics.gridRowGap) {
                ForEach(0..<12, id: \.self) { _ in Skeleton(.poster) }
            }
            .accessibilityHidden(true)
        } else if content.isEmpty {
            message(emptyMessage)
        } else {
            let tail = Set(content.items.suffix(LibraryGridMapper.prefetchDistance).map(\.id))
            LazyVGrid(columns: columns, alignment: .leading, spacing: metrics.gridRowGap) {
                ForEach(content.items) { model in
                    PosterCard(model) { onOpen(model.detailId) }
                        .onAppear { if tail.contains(model.id), !content.isComplete { onLoadMore() } }
                }
            }
            footer
        }
    }

    @ViewBuilder
    private var footer: some View {
        if loadMoreFailed {
            PillButton(String(localized: "Réessayer"), systemImage: "arrow.clockwise", action: onLoadMore)
                .frame(maxWidth: .infinity)
        } else if isLoadingMore {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(Design.Typography.body)
            .foregroundStyle(Design.Palette.textSecondary)
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: metrics.poster.width), spacing: metrics.shelfGap, alignment: .top)]
    }
}

/// A titled screen made of one poster grid (« Voir tout », a collection, a person).
struct PosterGridView: View {
    @Environment(\.designMetrics) private var metrics
    let title: String
    let content: PosterGridContent
    let isLoading: Bool
    let failureMessage: String?
    var emptyMessage = String(localized: "Rien à afficher pour l'instant.")
    var isLoadingMore = false
    var loadMoreFailed = false
    let onOpen: (String) -> Void
    var onLoadMore: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.focusInset) {
                Text(title)
                    .font(Design.Typography.title)
                    .foregroundStyle(Design.Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                PosterGrid(
                    content: content, isLoading: isLoading, failureMessage: failureMessage, emptyMessage: emptyMessage,
                    isLoadingMore: isLoadingMore, loadMoreFailed: loadMoreFailed, onOpen: onOpen, onLoadMore: onLoadMore
                )
            }
            .padding(.horizontal, metrics.screenMargin)
            .padding(.vertical, metrics.safeVertical)
        }
        .scrollClipDisabled()
    }
}
