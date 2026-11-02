import Foundation
import Testing
@testable import DesignSystem

@Suite struct OSDModelTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: hour, minute: minute))!
    }

    @Test func clockAlwaysShowsHours() {
        #expect(OSDModel.clock(0) == "0:00:00")
        #expect(OSDModel.clock(1164) == "0:19:24")
        #expect(OSDModel.clock(3661) == "1:01:01")
    }

    @Test func clockRoundsAndSanitizes() {
        #expect(OSDModel.clock(59.9) == "0:00:59")
        #expect(OSDModel.clock(59.1, rounding: .up) == "0:01:00")
        #expect(OSDModel.clock(-5) == "0:00:00")
        #expect(OSDModel.clock(.nan) == "0:00:00")
    }

    @Test func valuesFromPosition() {
        let model = OSDModel(title: "T", position: 1164, duration: 2760, now: date(20, 0), calendar: utc)
        #expect(model.elapsed == "0:19:24")
        #expect(model.remaining == "-0:26:36")
        #expect(abs(model.progress - 1164.0 / 2760.0) < 1e-9)
        #expect(model.preview == nil)
    }

    @Test func endTimeIsNowPlusRemaining() {
        let locale = Locale(identifier: testUsesEnglish ? "en_US" : "fr_FR")
        // 20:00 + 26 min 36 s = 20:26:36 -> 20 h 26.
        #expect(OSDModel.endTime(now: date(20, 0), remaining: 1596, calendar: utc, locale: locale).replacingOccurrences(of: "\u{202F}", with: " ") == tr(fr: "Se termine à 20 h 26", en: "Ends at 8:26 PM"))
        // Crosses midnight and pads minutes.
        #expect(OSDModel.endTime(now: date(23, 30), remaining: 2100, calendar: utc, locale: locale).replacingOccurrences(of: "\u{202F}", with: " ") == tr(fr: "Se termine à 0 h 05", en: "Ends at 12:05 AM"))
        #expect(OSDModel.endTime(now: date(21, 0), remaining: 6420, calendar: utc, locale: locale).replacingOccurrences(of: "\u{202F}", with: " ") == tr(fr: "Se termine à 22 h 47", en: "Ends at 10:47 PM"))
    }

    @Test func scrubbingShowsPreviewAtTarget() {
        let model = OSDModel(title: "T", position: 600, duration: 3000, isScrubbing: true, now: date(20, 0), calendar: utc)
        #expect(model.preview == "0:10:00")
        #expect(model.elapsed == "0:10:00")
        #expect(model.progress == 0.2)
    }

    @Test func unknownDurationHidesRemainingAndEnd() {
        let model = OSDModel(title: "T", position: 30, duration: 0)
        #expect(model.remaining == nil)
        #expect(model.endsAt == nil)
        #expect(model.progress == 0)
    }

    @Test func progressNeverExceedsOne() {
        #expect(OSDModel(title: "T", position: 5000, duration: 3000).progress == 1)
    }

    @Test func movieHeadingIsItsTitle() {
        #expect(OSDModel.heading(name: "Dune", seriesName: nil, season: nil, episode: nil) == "Dune")
    }

    @Test func episodeHeadingNamesSeriesSeasonAndEpisode() {
        #expect(OSDModel.heading(name: "Fréquence zéro", seriesName: "Fréquences", season: 2, episode: 5)
            == "Fréquences › S2E5 · Fréquence zéro")
        #expect(OSDModel.heading(name: "Pilote", seriesName: "Série", season: nil, episode: 1) == "Série › E1 · Pilote")
        #expect(OSDModel.heading(name: "Pilote", seriesName: "Série", season: nil, episode: nil) == "Série › Pilote")
    }
}

@Suite struct TransportMathTests {
    @Test func skipsTenSeconds() {
        #expect(TransportMath.skipTarget(from: 100, direction: .forward, duration: 3000) == 110)
        #expect(TransportMath.skipTarget(from: 100, direction: .backward, duration: 3000) == 90)
    }

    @Test func skipStaysInsideTheFile() {
        #expect(TransportMath.skipTarget(from: 4, direction: .backward, duration: 3000) == 0)
        #expect(TransportMath.skipTarget(from: 2995, direction: .forward, duration: 3000) == 3000)
    }

    @Test func unknownDurationOnlyBoundsTheStart() {
        #expect(TransportMath.skipTarget(from: 4, direction: .backward, duration: 0) == 0)
        #expect(TransportMath.skipTarget(from: 100, direction: .forward, duration: 0) == 110)
    }

    @Test func seekTrackerHoldsTheTargetUntilThePlayerArrives() {
        var tracker = SeekTracker()
        let t0 = Date(timeIntervalSince1970: 1000)
        tracker.seek(to: 110, at: t0)
        // Still at the old position: the target wins.
        #expect(tracker.position(playerPosition: 100, at: t0.addingTimeInterval(0.5)) == 110)
        // Arrived (within tolerance): the player's own position.
        #expect(tracker.position(playerPosition: 109, at: t0.addingTimeInterval(1)) == 109)
        // Never landed: gives up after the timeout.
        #expect(tracker.position(playerPosition: 100, at: t0.addingTimeInterval(SeekTracker.settleTimeout + 1)) == 100)
    }

    @Test func repeatedSkipsBuildOnThePendingTarget() {
        var tracker = SeekTracker()
        let t0 = Date(timeIntervalSince1970: 1000)
        tracker.seek(to: 110, at: t0)
        let next = TransportMath.skipTarget(from: tracker.position(playerPosition: 100, at: t0), direction: .forward, duration: 3000)
        #expect(next == 120)
    }

    @Test func scrubSpanScalesWithDurationWithinBounds() {
        #expect(ScrubSession.span(duration: 300) == 60)
        #expect(ScrubSession.span(duration: 3000) == 300)
        #expect(ScrubSession.span(duration: 20_000) == 600)
    }

    @Test func scrubFollowsTheSwipeFromWhereItStarted() {
        var session = ScrubSession(origin: 1000, duration: 3000)
        session.beginPan()
        session.pan(fraction: 0.5)
        #expect(session.target == 1150)
        // A second swipe continues from the preview.
        session.beginPan()
        session.pan(fraction: -1)
        #expect(session.target == 850)
        #expect(session.origin == 1000)
    }

    @Test func scrubIsClamped() {
        var session = ScrubSession(origin: 100, duration: 3000)
        session.beginPan()
        session.pan(fraction: -5)
        #expect(session.target == 0)
        session.pan(fraction: 50)
        #expect(session.target == 3000)
    }

    @Test func scrubNudgeMovesTenSeconds() {
        var session = ScrubSession(origin: 100, duration: 3000)
        session.nudge(.forward)
        session.nudge(.forward)
        #expect(session.target == 120)
        session.beginPan()
        session.pan(fraction: 0)
        #expect(session.target == 120)
    }
}

@Suite struct OSDVisibilityTests {
    private let t0 = Date(timeIntervalSince1970: 1000)

    @Test func startsHidden() {
        #expect(!OSDVisibility().isVisible)
    }

    @Test func playingRevealHidesAfterTheInactivityDelay() {
        var visibility = OSDVisibility()
        visibility.reveal(isPlaying: true, now: t0)
        #expect(visibility.isVisible)
        #expect(visibility.deadline == t0.addingTimeInterval(OSDVisibility.inactivityDelay))
        visibility.expire(now: t0.addingTimeInterval(OSDVisibility.inactivityDelay - 0.1))
        #expect(visibility.isVisible)
        visibility.expire(now: t0.addingTimeInterval(OSDVisibility.inactivityDelay))
        #expect(!visibility.isVisible)
    }

    @Test func pausedRevealNeverExpires() {
        var visibility = OSDVisibility()
        visibility.reveal(isPlaying: false, now: t0)
        #expect(visibility.deadline == nil)
        visibility.expire(now: t0.addingTimeInterval(3600))
        #expect(visibility.isVisible)
    }

    @Test func anotherInteractionRestartsTheTimer() {
        var visibility = OSDVisibility()
        visibility.reveal(isPlaying: true, now: t0)
        visibility.reveal(isPlaying: true, now: t0.addingTimeInterval(3))
        visibility.expire(now: t0.addingTimeInterval(5))
        #expect(visibility.isVisible)
        visibility.expire(now: t0.addingTimeInterval(7))
        #expect(!visibility.isVisible)
    }
}

@MainActor @Suite struct TransportControllerTests {
    /// A fake player the controller drives.
    @MainActor final class Player {
        var position = 100.0
        var duration = 3000.0
        var isPaused = false
        var seeks: [Double] = []
        var clock = Date(timeIntervalSince1970: 1000)

        func controller() -> TransportController {
            TransportController(
                driver: .init(
                    position: { self.seeks.last ?? self.position }, duration: { self.duration },
                    isPaused: { self.isPaused }, seek: { self.seeks.append($0) }, setPaused: { self.isPaused = $0 }
                ),
                now: { self.clock }
            )
        }
    }

    @Test func touchRevealsThenTheDisplayFades() {
        let player = Player()
        let transport = player.controller()
        transport.reveal()
        #expect(transport.state.isVisible)
        player.clock.addTimeInterval(OSDVisibility.inactivityDelay + 0.1)
        transport.expire()
        #expect(!transport.state.isVisible)
    }

    @Test func pauseKeepsTheDisplayAndResumeRearmsTheTimer() {
        let player = Player()
        let transport = player.controller()
        transport.playPause()
        #expect(player.isPaused)
        #expect(transport.visibility.isVisible)
        #expect(transport.visibility.deadline == nil)
        transport.playPause()
        #expect(!player.isPaused)
        #expect(transport.visibility.deadline != nil)
    }

    @Test func aPendingSeekIsSettlingUntilThePlayerLands() {
        var tracker = SeekTracker()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(!tracker.isSettling(playerPosition: 100, at: start))
        tracker.seek(to: 300, at: start)
        #expect(tracker.isSettling(playerPosition: 100, at: start))
        #expect(!tracker.isSettling(playerPosition: 299, at: start.addingTimeInterval(0.5)))
        #expect(!tracker.isSettling(playerPosition: 100, at: start.addingTimeInterval(SeekTracker.settleTimeout + 0.1)))
    }

    @Test func playPauseCommitsAScrubInOnePress() {
        let player = Player()
        let transport = player.controller()
        transport.playPause()
        #expect(player.isPaused)
        transport.panBegan()
        transport.pan(fraction: 0.1)
        let target = transport.displayedPosition
        transport.playPause()
        #expect(!transport.isScrubbing)
        #expect(player.seeks.last == target)
        #expect(!player.isPaused)
    }

    @Test func clicksSkipTenSecondsAndBuildOnEachOther() {
        let player = Player()
        let transport = player.controller()
        transport.skip(.forward)
        transport.skip(.forward)
        transport.skip(.backward)
        #expect(player.seeks == [110, 120, 110])
        #expect(transport.skipFeedback?.direction == .backward)
        #expect(transport.visibility.isVisible)
    }

    @Test func repeatedSkipsGetNewFeedbackTokens() {
        let player = Player()
        let transport = player.controller()
        transport.skip(.forward)
        let first = transport.skipFeedback?.token
        transport.skip(.forward)
        #expect(transport.skipFeedback?.token != first)
        transport.clearSkipFeedback(token: first!)
        #expect(transport.skipFeedback != nil)
        transport.clearSkipFeedback(token: transport.skipFeedback!.token)
        #expect(transport.skipFeedback == nil)
    }

    @Test func swipeWhilePlayingOnlyRevealsTheDisplay() {
        let player = Player()
        let transport = player.controller()
        transport.panBegan()
        #expect(transport.visibility.isVisible)
        #expect(!transport.isScrubbing)
    }

    @Test func scrubPreviewsThenSelectSeeksAndResumes() {
        let player = Player()
        player.isPaused = true
        let transport = player.controller()
        transport.panBegan()
        transport.pan(fraction: 0.5)
        #expect(transport.isScrubbing)
        #expect(transport.displayedPosition == 250)
        #expect(player.seeks.isEmpty)
        transport.select()
        #expect(player.seeks == [250])
        #expect(!player.isPaused)
        #expect(!transport.isScrubbing)
        #expect(transport.visibility.deadline != nil)
    }

    @Test func menuDuringScrubCancelsWithoutSeeking() {
        let player = Player()
        player.isPaused = true
        let transport = player.controller()
        transport.panBegan()
        transport.pan(fraction: 0.5)
        #expect(transport.menu() == .handled)
        #expect(!transport.isScrubbing)
        #expect(player.seeks.isEmpty)
        #expect(player.isPaused)
        #expect(transport.displayedPosition == 100)
        #expect(transport.visibility.isVisible)
    }

    @Test func clickWhileScrubbingNudgesThePreview() {
        let player = Player()
        player.isPaused = true
        let transport = player.controller()
        transport.panBegan()
        transport.skip(.forward)
        #expect(transport.displayedPosition == 110)
        #expect(player.seeks.isEmpty)
    }

    @Test func menuClosesTheDisplayThenLeaves() {
        let player = Player()
        let transport = player.controller()
        transport.reveal()
        #expect(transport.menu() == .handled)
        #expect(!transport.visibility.isVisible)
        #expect(transport.menu() == .exit)
    }

    @Test func displayStaysWhilePausedEvenIfPausedFromOutside() {
        let player = Player()
        let transport = player.controller()
        transport.reveal()
        player.isPaused = true
        transport.pausedChanged(true)
        player.clock.addTimeInterval(60)
        transport.expire()
        #expect(transport.visibility.isVisible)
    }
}
