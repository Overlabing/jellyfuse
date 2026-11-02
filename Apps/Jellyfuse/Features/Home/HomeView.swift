import DesignSystem
import HomePresentation
import LibraryKit
import SwiftUI

/// Pure home layout (home.html): billboard, then « À suivre » then one « Ajouts récents » shelf per library. Props in, callbacks out.
struct HomeView: View {
    @Environment(\.designMetrics) private var metrics
    let content: HomeContent
    let isLoadingCold: Bool
    let failureMessage: String?
    let onPlay: (String) -> Void
    let onSeeAll: (Library) -> Void
    let onToggleList: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let billboard = content.billboard {
                    Billboard(
                        billboard.model,
                        primaryLabel: billboard.primaryLabel,
                        onPlay: { onPlay(billboard.target.id) },
                        onToggleList: onToggleList
                    )
                } else if isLoadingCold {
                    BillboardSkeleton()
                } else {
                    EmptyHome(message: failureMessage)
                }
                if !content.upNext.isEmpty {
                    Shelf(title: String(localized: "À suivre"), items: content.upNext) { model in
                        LandscapeCard(model) { onPlay(model.id) }
                    }
                } else if isLoadingCold {
                    SkeletonShelf(title: String(localized: "À suivre"), kind: .landscape)
                }
                if content.libraryShelves.isEmpty, isLoadingCold {
                    SkeletonShelf(title: String(localized: "Ajouts récents"), kind: .poster)
                }
                ForEach(content.libraryShelves) { shelf in
                    if !shelf.items.isEmpty {
                        Shelf(title: shelf.title, items: shelf.items) { model in
                            PosterCard(model) { onPlay(model.id) }
                        } trailing: {
                            SeeAllCard { onSeeAll(shelf.library) }
                        }
                        .padding(.top, metrics.gridRowGap - 2 * metrics.focusInset)
                    } else if isLoadingCold {
                        SkeletonShelf(title: shelf.title, kind: .poster)
                    }
                }
            }
            .padding(.bottom, metrics.safeVertical)
        }
        .ignoresSafeArea(edges: .top)
        .scrollClipDisabled()
    }
}

private struct SkeletonSlot: Identifiable {
    let id: Int
}

private struct SkeletonShelf: View {
    let title: String
    let kind: Skeleton.Kind

    var body: some View {
        Shelf(title: title, items: (0..<5).map(SkeletonSlot.init)) { _ in Skeleton(kind) }
            .accessibilityHidden(true)
    }
}

private struct BillboardSkeleton: View {
    @Environment(\.designMetrics) private var metrics

    var body: some View {
        BackdropView(ArtworkSource(url: nil, placeholderTitle: ""))
            .frame(maxWidth: .infinity)
            .frame(height: metrics.billboardHeight)
            .accessibilityHidden(true)
    }
}

private struct EmptyHome: View {
    @Environment(\.designMetrics) private var metrics
    let message: String?

    var body: some View {
        Text(message ?? String(localized: "Rien à afficher pour l'instant."))
            .font(Design.Typography.body)
            .foregroundStyle(Design.Palette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: metrics.billboardHeight)
    }
}
