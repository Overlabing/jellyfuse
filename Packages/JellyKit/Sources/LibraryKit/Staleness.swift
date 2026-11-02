import Foundation

/// The kinds of cached resource. Every freshness duration lives here and nowhere else
/// (data-plan §3.1); values are inherited from the RN `STALE_TIMES`, not measured.
public enum ResourceKind: String, Sendable, CaseIterable, Codable {
    case continueWatching
    case nextUp
    case seriesNextUp
    case recentlyAdded
    case latestMovies
    case latestTV
    case suggestions
    case shelfPage
    case detail
    case children
    case adjacentEpisode
    case views
    case config

    public var staleTime: Duration {
        switch self {
        case .continueWatching, .nextUp, .seriesNextUp: .seconds(60)
        case .recentlyAdded, .latestMovies, .latestTV, .children, .adjacentEpisode, .shelfPage: .seconds(300)
        case .suggestions, .detail: .seconds(120)
        case .views, .config: .seconds(3600)
        }
    }

    /// Written to disk. Home shelves only in v1 (data-plan Q3); default is "no".
    public var isPersisted: Bool {
        switch self {
        case .continueWatching, .nextUp, .recentlyAdded, .latestMovies, .latestTV, .views: true
        case .seriesNextUp, .suggestions, .shelfPage, .detail, .children, .adjacentEpisode, .config: false
        }
    }
}

/// A value and the moment it was fetched. Hydrated snapshots carry `.distantPast`: painted at once, revalidated next.
public struct Stamped<Value: Sendable & Equatable>: Sendable, Equatable {
    public var value: Value
    public var fetchedAt: Date

    public init(_ value: Value, fetchedAt: Date) {
        self.value = value
        self.fetchedAt = fetchedAt
    }

    public func isStale(for kind: ResourceKind, now: Date) -> Bool {
        now.timeIntervalSince(fetchedAt) > kind.staleTime.seconds
    }
}

extension Duration {
    var seconds: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
