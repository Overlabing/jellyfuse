import DesignSystem
import HomePresentation
import SwiftUI

/// Pure search layout (search.html): results grouped in shelves (Films, Séries, Épisodes). Before a
/// query is worth running it shows the « Ajouts récents » shelves the home already loaded.
/// Props in, callbacks out.
struct SearchView: View {
    @Environment(\.designMetrics) private var metrics
    let phase: SearchModel.Phase
    let content: SearchContent
    let recents: [LibraryShelfContent]
    let onOpenDetail: (String) -> Void
    let onRetry: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                switch phase {
                case .idle:
                    ForEach(recents.filter { !$0.items.isEmpty }) { shelf in
                        Shelf(title: shelf.title, items: shelf.items) { model in
                            PosterCard(model) { onOpenDetail(model.detailId) }
                        }
                    }
                case .empty(let term):
                    Message(String(localized: "Aucun résultat pour « \(term) »"))
                case .failed:
                    VStack(spacing: metrics.shelfGap) {
                        Message(String(localized: "La recherche n'a pas abouti."))
                        PillButton(String(localized: "Réessayer"), systemImage: "arrow.clockwise", action: onRetry)
                    }
                case .loading, .results:
                    results
                }
            }
            .padding(.bottom, metrics.safeVertical)
        }
        .scrollClipDisabled()
        .dismissesKeyboardOnScroll()
    }

    @ViewBuilder private var results: some View {
        if !content.movies.isEmpty {
            Shelf(title: String(localized: "Films"), items: content.movies) { model in
                PosterCard(model) { onOpenDetail(model.detailId) }
            }
        }
        if !content.series.isEmpty {
            Shelf(title: String(localized: "Séries"), items: content.series) { model in
                PosterCard(model) { onOpenDetail(model.detailId) }
            }
        }
        if !content.episodes.isEmpty {
            Shelf(title: String(localized: "Épisodes"), items: content.episodes) { model in
                LandscapeCard(model) { onOpenDetail(content.detailId(for: model.id)) }
            }
        }
    }
}

private struct Message: View {
    @Environment(\.designMetrics) private var metrics
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Design.Typography.body)
            .foregroundStyle(Design.Palette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: metrics.billboardHeight / 2)
    }
}
