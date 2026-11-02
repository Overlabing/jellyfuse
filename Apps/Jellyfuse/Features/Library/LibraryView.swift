import DesignSystem
import HomePresentation
import SwiftUI

/// Pure layout of a Films / Séries tab (library.html): title with the « Filtres et tri » button, the
/// collections row (Films), then the paginated poster grid. Props in, callbacks out.
struct LibraryView: View {
    @Environment(\.designMetrics) private var metrics
    let title: String
    let summary: String
    let content: PosterGridContent
    let collections: [PosterModel]
    let isLoading: Bool
    let failureMessage: String?
    let emptyMessage: String
    let isLoadingMore: Bool
    let loadMoreFailed: Bool
    /// Changes whenever the grid is replaced (sort, filter, jump): the scroll goes back to the top.
    let scrollResetToken: AnyHashable
    let onOpenFilters: () -> Void
    let onOpen: (String) -> Void
    let onLoadMore: () -> Void

    private static let top = "library.top"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header.id(Self.top)
                    if !collections.isEmpty {
                        Shelf(title: String(localized: "Collections"), items: collections) { model in
                            PosterCard(model) { onOpen(model.detailId) }
                        }
                        .padding(.bottom, metrics.gridRowGap - 2 * metrics.focusInset)
                    }
                    VStack(alignment: .leading, spacing: metrics.focusInset) {
                        if !collections.isEmpty {
                            Text(title)
                                .font(Design.Typography.sectionTitle)
                                .foregroundStyle(Design.Palette.textPrimary)
                                .accessibilityAddTraits(.isHeader)
                        }
                        PosterGrid(
                            content: content, isLoading: isLoading, failureMessage: failureMessage, emptyMessage: emptyMessage,
                            isLoadingMore: isLoadingMore, loadMoreFailed: loadMoreFailed, onOpen: onOpen, onLoadMore: onLoadMore
                        )
                    }
                    .padding(.horizontal, metrics.screenMargin)
                }
                .padding(.vertical, metrics.safeVertical)
            }
            .scrollClipDisabled()
            .onChange(of: scrollResetToken) { proxy.scrollTo(Self.top, anchor: .top) }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Design.Spacing.m) {
            Text(title)
                .font(Design.Typography.title)
                .foregroundStyle(Design.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Design.Spacing.m)
            Text(([summary] + [content.total.map { String(localized: "\($0.formatted()) titres") }].compactMap { $0 }).joined(separator: " · "))
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Palette.textSecondary)
                .lineLimit(1)
            PillButton(String(localized: "Filtres et tri"), systemImage: "line.3.horizontal.decrease", action: onOpenFilters)
                .accessibilityIdentifier("library.filters")
        }
        .padding(.horizontal, metrics.screenMargin)
        .padding(.bottom, metrics.focusInset)
    }
}
