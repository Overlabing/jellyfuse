import HomePresentation
import LibraryKit
import SwiftUI

/// Composition layer of the « Voir tout » grid: a library's items, newest added first. No filters, no sort.
struct RecentGridScreen: View {
    let model: HomeModel
    let library: Library
    let onOpen: (String) -> Void
    @State private var hasLoaded = false
    @State private var failure: UserFacingError?

    var body: some View {
        let content = model.grid(for: library)
        PosterGridView(
            title: library.name,
            content: PosterGridContent(items: content.items, total: nil, isComplete: true),
            isLoading: !hasLoaded && content.isEmpty,
            failureMessage: content.isEmpty ? failure.map { _ in String(localized: "Impossible de charger la bibliothèque.") } : nil,
            onOpen: onOpen
        )
        .task {
            failure = await model.refreshGrid(for: library)
            hasLoaded = true
        }
    }
}

/// A fixed paginated grid: the films of a collection, the credits of a person.
struct FixedGridScreen: View {
    let title: String
    let key: GridKey
    let onOpen: (String) -> Void
    @State private var model: GridModel

    init(title: String, key: GridKey, model: GridModel, onOpen: @escaping (String) -> Void) {
        self.title = title
        self.key = key
        self.onOpen = onOpen
        _model = State(initialValue: model)
    }

    var body: some View {
        PosterGridView(
            title: title,
            content: model.content(for: key),
            isLoading: model.isLoading(key),
            failureMessage: model.failure(for: key).map { _ in String(localized: "Impossible de charger la liste.") },
            isLoadingMore: model.isLoadingMore,
            loadMoreFailed: model.loadMoreFailed,
            onOpen: onOpen,
            onLoadMore: { Task { await model.loadMore(key) } }
        )
        .task { await model.refresh(key) }
    }
}
