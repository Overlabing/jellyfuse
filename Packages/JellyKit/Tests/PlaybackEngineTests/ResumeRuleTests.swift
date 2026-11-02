import Foundation
import LibraryKit
import Testing
@testable import PlaybackEngine

@Suite struct ResumeRuleTests {
    // Thresholds as a server states them; the rule reads them, it does not know them.
    private let thresholds = ResumeThresholds(minPercent: 5, maxPercent: 90, minDurationSeconds: 300)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let hour: Int64 = 36_000_000_000

    private func apply(position: Int64, runtime: Int64? = 36_000_000_000, from: UserData = .none) -> UserData {
        ResumeRule.apply(to: from, positionTicks: position, runtimeTicks: runtime, thresholds: thresholds, now: now)
    }

    @Test func belowMinPercentResetsToUnwatched() {
        let watchedBefore = UserData(played: true, playbackPositionTicks: 5, playCount: 2, isFavorite: true, lastPlayedDate: nil)
        let result = apply(position: hour / 100, from: watchedBefore)
        #expect(result.playbackPositionTicks == 0 && !result.played)
        #expect(result.isFavorite && result.playCount == 2)
    }

    @Test func aboveMaxPercentIsWatchedWithNoResume() {
        let result = apply(position: hour * 95 / 100)
        #expect(result.playbackPositionTicks == 0 && result.played && result.playCount == 1)
        #expect(result.lastPlayedDate == now)
    }

    @Test func lessThanASecondFromTheEndIsWatched() {
        #expect(apply(position: hour - 5_000_000, runtime: hour).played)
    }

    @Test func middleOfTheFileKeepsThePosition() {
        let result = apply(position: hour / 2)
        #expect(result.playbackPositionTicks == hour / 2 && !result.played)
    }

    @Test func shortItemsAreWatchedOnceStartedPastMinPercent() {
        let short: Int64 = 1_200_000_000  // 2 minutes
        let result = apply(position: short / 2, runtime: short)
        #expect(result.played && result.playbackPositionTicks == 0)
    }

    @Test func unknownRuntimeKeepsThePositionOnly() {
        let result = apply(position: 777, runtime: nil)
        #expect(result.playbackPositionTicks == 777 && !result.played)
    }
}
