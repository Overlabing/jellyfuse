import Foundation
import LibraryKit
import Testing
@testable import PlayerPresentation

/// Ported from the RN client's `end-of-episode-gate.test.ts` and `end-of-episode-store.ts`.
@Suite struct EndOfEpisodeTests {
    private func phase(
        _ position: Double, _ duration: Double, credits: ClosedRange<Double>? = nil, hasNext: Bool = true
    ) -> EndOfEpisodePhase {
        EndOfEpisodeGate.targetPhase(position: position, duration: duration, credits: credits, hasNext: hasNext)
    }

    // MARK: Idle

    @Test func idleBeforeMpvHasLoaded() { #expect(phase(0, 0) == .idle) }
    @Test func idleForShortItemsOutsideCredits() { #expect(phase(500, 590) == .idle) }
    @Test func idleInTheBulkOfAnEpisode() { #expect(phase(600, 1800) == .idle) }
    @Test func idleInTheFinal20sTooCloseForACountdown() { #expect(phase(1790, 1800) == .idle) }

    // MARK: Credits path

    @Test func creditsInsideTheSegmentWithANextEpisode() { #expect(phase(1750, 1800, credits: 1740...1795) == .credits) }

    @Test func idleInCreditsWithoutANextEpisode() { #expect(phase(1750, 1800, credits: 1740...1795, hasNext: false) == .idle) }

    @Test func creditsIgnoreTheShortDurationGate() { #expect(phase(290, 300, credits: 285...299) == .credits) }

    // MARK: Near-end path

    @Test func nearEndShowsAt30sBelow40Minutes() { #expect(phase(1770, 1800) == .nearEnd) }
    @Test func nearEndShowsAt35sFrom40Minutes() { #expect(phase(2365, 2400) == .nearEnd) }
    @Test func nearEndShowsAt40sFrom50Minutes() { #expect(phase(2960, 3000) == .nearEnd) }
    @Test func nearEndWaitsForItsWindow() { #expect(phase(1700, 1800) == .idle) }

    @Test func creditsPathHasPriorityOverNearEnd() { #expect(phase(1775, 1800, credits: 1770...1790) == .credits) }

    @Test func nearEndTakesOverAfterTheCreditsEnd() { #expect(phase(1775, 1800, credits: 1700...1740) == .nearEnd) }

    @Test func nearEndIsSuppressedWhileInsideCreditsWithoutANext() {
        #expect(phase(1775, 1800, credits: 1770...1790, hasNext: false) == .idle)
    }

    @Test func theGateItselfDoesNotLookAtHasNextForNearEnd() { #expect(phase(1770, 1800, hasNext: false) == .nearEnd) }

    // MARK: Boundaries

    @Test func creditsStartIsInclusiveEndExclusive() {
        #expect(phase(1740, 1800, credits: 1740...1795) == .credits)
        #expect(phase(1795, 1800, credits: 1740...1795) == .idle)
    }

    @Test func exactly20sRemainingTriggers() { #expect(phase(1780, 1800) == .nearEnd) }

    // MARK: State and latches

    @Test func enteringTwiceChangesNothing() {
        var state = EndOfEpisodeState()
        state.enter(.credits)
        state.enter(.credits)
        #expect(state.phase == .credits)
    }

    @Test func watchCreditsLocksTheCreditsPathOnly() {
        var state = EndOfEpisodeState()
        state.enter(.credits)
        state.watchCredits()
        #expect(state.phase == .idle)
        state.enter(.credits)
        #expect(state.phase == .idle)
        state.enter(.nearEnd)
        #expect(state.phase == .nearEnd)
    }

    @Test func dismissLatchesTheActivePathOnly() {
        var state = EndOfEpisodeState()
        state.enter(.nearEnd)
        state.dismiss()
        #expect(state.nearEndDismissed && !state.creditsDismissed)
        state.enter(.nearEnd)
        #expect(state.phase == .idle)
        state.enter(.credits)
        #expect(state.phase == .credits)
    }

    @Test func dismissWhileIdleLatchesNothing() {
        var state = EndOfEpisodeState()
        state.dismiss()
        #expect(!state.isDismissed)
    }

    @Test func completingDoesNotLatchSoABackwardSeekShowsTheCardAgain() {
        var state = EndOfEpisodeState()
        state.enter(.nearEnd)
        state.complete()
        #expect(state.phase == .idle && !state.isDismissed)
        state.enter(.nearEnd)
        #expect(state.phase == .nearEnd)
    }

    @Test func resetClearsEveryLatch() {
        var state = EndOfEpisodeState()
        state.enter(.credits)
        state.dismiss()
        state.reset()
        #expect(state == EndOfEpisodeState())
    }
}

@Suite struct UpNextTests {
    private func entry(_ id: String, season: Int, episode: Int) -> LibraryEntry {
        LibraryEntry(item: MediaItem(id: id, name: "Titre \(id)", kind: .episode, indexNumber: episode, parentIndexNumber: season))
    }

    private var episodes: [LibraryEntry] { [entry("a", season: 1, episode: 1), entry("b", season: 1, episode: 2), entry("c", season: 2, episode: 1)] }

    @Test func nextIsTheFollowingEpisodeAcrossSeasons() {
        #expect(UpNext.next(after: "a", in: episodes)?.id == "b")
        #expect(UpNext.next(after: "b", in: episodes)?.id == "c")
    }

    @Test func theLastEpisodeAndAnUnknownIdHaveNoNext() {
        #expect(UpNext.next(after: "c", in: episodes) == nil)
        #expect(UpNext.next(after: "zzz", in: episodes) == nil)
        #expect(UpNext.next(after: "a", in: []) == nil)
    }

    @Test func theCardNamesTheEpisodeWithItsCode() {
        #expect(UpNext.title(of: episodes[2].item) == "S2E1 · Titre c")
    }
}
