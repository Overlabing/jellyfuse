import Foundation
import Testing
@testable import LibraryKit

@Suite struct StalenessTests {
    @Test func tableHoldsTheValuesInheritedFromTheRN() {
        #expect(ResourceKind.continueWatching.staleTime == .seconds(60))
        #expect(ResourceKind.nextUp.staleTime == .seconds(60))
        #expect(ResourceKind.seriesNextUp.staleTime == .seconds(60))
        #expect(ResourceKind.recentlyAdded.staleTime == .seconds(300))
        #expect(ResourceKind.latestMovies.staleTime == .seconds(300))
        #expect(ResourceKind.latestTV.staleTime == .seconds(300))
        #expect(ResourceKind.suggestions.staleTime == .seconds(120))
        #expect(ResourceKind.detail.staleTime == .seconds(120))
        #expect(ResourceKind.children.staleTime == .seconds(300))
        #expect(ResourceKind.adjacentEpisode.staleTime == .seconds(300))
        #expect(ResourceKind.config.staleTime == .seconds(3600))
    }

    @Test func stampedIsFreshUpToTheIntervalThenStale() {
        let start = Date(timeIntervalSince1970: 1000)
        let stamped = Stamped([String](), fetchedAt: start)
        #expect(!stamped.isStale(for: .continueWatching, now: start))
        #expect(!stamped.isStale(for: .continueWatching, now: start.addingTimeInterval(60)))
        #expect(stamped.isStale(for: .continueWatching, now: start.addingTimeInterval(61)))
        #expect(!stamped.isStale(for: .recentlyAdded, now: start.addingTimeInterval(61)))
    }

    @Test func hydratedStampIsAlwaysStale() {
        let stamped = Stamped([String](), fetchedAt: .distantPast)
        for kind in ResourceKind.allCases {
            #expect(stamped.isStale(for: kind, now: Date(timeIntervalSince1970: 0)))
        }
    }

    @Test func onlyHomeShelvesAndViewsArePersisted() {
        let persisted = Set(ResourceKind.allCases.filter(\.isPersisted))
        #expect(persisted == [.continueWatching, .nextUp, .recentlyAdded, .latestMovies, .latestTV, .views])
        #expect(!ResourceKind.detail.isPersisted)
    }
}
