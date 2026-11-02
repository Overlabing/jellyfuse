import DesignSystem
import Foundation
import LibraryKit
import Observation

/// State of the search tab. Volatile by design: no staleness, no snapshot. Each keystroke restarts a
/// debounce; a newer query cancels the one in flight, and an answer that lost the race is dropped.
@MainActor
@Observable
public final class SearchModel {
    public enum Phase: Equatable, Sendable {
        /// Nothing worth searching yet (fewer than `SearchQuery.minimumLength` characters).
        case idle
        /// A request is pending; `content` still holds the previous results, if any.
        case loading
        case results
        /// The search ran and found nothing for this term.
        case empty(term: String)
        /// The request failed, after one silent retry.
        case failed(term: String)
    }

    public var query = "" {
        didSet { if query != oldValue { restart() } }
    }
    public private(set) var phase = Phase.idle
    public private(set) var content = SearchContent.empty

    private let api: any SearchAPI
    private let ingest: @MainActor ([LibraryEntry]) -> Void
    private let imageURL: HomeMapper.ImageURL
    private let debounce: Duration
    private let retryDelay: Duration
    private var task: Task<Void, Never>?

    public init(
        api: any SearchAPI,
        ingest: @escaping @MainActor ([LibraryEntry]) -> Void,
        imageURL: @escaping HomeMapper.ImageURL,
        debounce: Duration = .milliseconds(300),
        retryDelay: Duration = .seconds(1)
    ) {
        self.api = api
        self.ingest = ingest
        self.imageURL = imageURL
        self.debounce = debounce
        self.retryDelay = retryDelay
    }

    /// Runs the current query again right away (the « Réessayer » button).
    public func retry() {
        guard let search = SearchQuery(query) else { return }
        launch(search, after: .zero)
    }

    /// Waits for the search in flight, if any (tests and previews).
    public func settled() async {
        await task?.value
    }

    private func restart() {
        guard let search = SearchQuery(query) else {
            task?.cancel()
            task = nil
            phase = .idle
            content = .empty
            return
        }
        launch(search, after: debounce)
    }

    private func launch(_ search: SearchQuery, after delay: Duration) {
        task?.cancel()
        phase = .loading
        task = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            await self?.run(search)
        }
    }

    private func run(_ search: SearchQuery) async {
        var outcome = await fetch(search)
        if outcome == nil, !Task.isCancelled {
            try? await Task.sleep(for: retryDelay)
            if !Task.isCancelled { outcome = await fetch(search) }
        }
        // A newer query replaced this one while it was in flight: its answer is stale.
        guard !Task.isCancelled, SearchQuery(query) == search else { return }
        guard let outcome else {
            phase = .failed(term: search.term)
            return
        }
        ingest(outcome.movies + outcome.series + outcome.episodes)
        content = SearchMapper.content(movies: outcome.movies, series: outcome.series, episodes: outcome.episodes, imageURL: imageURL)
        phase = content.isEmpty ? .empty(term: search.term) : .results
    }

    private struct Outcome {
        let movies: [LibraryEntry]
        let series: [LibraryEntry]
        let episodes: [LibraryEntry]
    }

    /// The three kinds in parallel; nil when any of them failed.
    private func fetch(_ search: SearchQuery) async -> Outcome? {
        let api = api
        let limit = SearchQuery.limitPerKind
        do {
            return try await withThrowingTaskGroup(of: (SearchKind, [LibraryEntry]).self) { group in
                for kind in SearchKind.allCases {
                    group.addTask { (kind, try await api.search(search, kind: kind, limit: limit)) }
                }
                var found: [SearchKind: [LibraryEntry]] = [:]
                for try await (kind, entries) in group { found[kind] = entries }
                return Outcome(movies: found[.movie] ?? [], series: found[.series] ?? [], episodes: found[.episode] ?? [])
            }
        } catch {
            return nil
        }
    }
}
