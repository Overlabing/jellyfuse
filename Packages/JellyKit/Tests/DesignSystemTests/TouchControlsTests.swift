import Foundation
import Testing
@testable import DesignSystem

@Suite struct TouchMathTests {
    @Test func doubleTapSidesPickTheSkipDirection() {
        #expect(TouchMath.skipDirection(tapX: 100, width: 800) == .backward)
        #expect(TouchMath.skipDirection(tapX: 399, width: 800) == .backward)
        #expect(TouchMath.skipDirection(tapX: 400, width: 800) == .forward)
        #expect(TouchMath.skipDirection(tapX: 790, width: 800) == .forward)
    }

    @Test func touchMapsToProgressWithoutChapters() {
        let segments = ChapterMarks.segments(marks: [])
        #expect(ChapterMarks.progress(atX: 0, segments: segments, width: 400, gap: 3) == 0)
        #expect(ChapterMarks.progress(atX: 100, segments: segments, width: 400, gap: 3) == 0.25)
        #expect(ChapterMarks.progress(atX: 400, segments: segments, width: 400, gap: 3) == 1)
    }

    @Test func touchOutsideTheBarClamps() {
        let segments = ChapterMarks.segments(marks: [0.5])
        #expect(ChapterMarks.progress(atX: -50, segments: segments, width: 400, gap: 4) == 0)
        #expect(ChapterMarks.progress(atX: 900, segments: segments, width: 400, gap: 4) == 1)
    }

    @Test func progressIsTheInverseOfPlayheadX() {
        let segments = ChapterMarks.segments(marks: [0.2, 0.6])
        for progress in stride(from: 0.0, through: 1.0, by: 0.05) {
            let x = ChapterMarks.playheadX(progress: progress, segments: segments, width: 500, gap: 6)
            let back = ChapterMarks.progress(atX: x, segments: segments, width: 500, gap: 6)
            #expect(abs(back - progress) < 1e-9, "progress \(progress)")
        }
    }

    @Test func touchInAGapSnapsToTheBoundary() {
        // width 406, gap 6, one mark at 0.5: each segment is 200 pt, the gap spans 200...206.
        let segments = ChapterMarks.segments(marks: [0.5])
        #expect(ChapterMarks.progress(atX: 203, segments: segments, width: 406, gap: 6) == 0.5)
    }

    @Test func scrubSessionFollowsTheFingerAbsolutely() {
        var session = ScrubSession(origin: 100, duration: 2000)
        session.scrub(toFraction: 0.5)
        #expect(session.target == 1000)
        session.scrub(toFraction: 1.4)
        #expect(session.target == 2000)
        session.scrub(toFraction: -1)
        #expect(session.target == 0)
        session.scrub(toFraction: .nan)
        #expect(session.target == 0)
    }
}

@MainActor @Suite struct TouchTransportTests {
    typealias Player = TransportControllerTests.Player

    @Test func tapTogglesTheDisplay() {
        let player = Player()
        let transport = player.controller()
        transport.toggleDisplay()
        #expect(transport.state.isVisible)
        transport.toggleDisplay()
        #expect(!transport.state.isVisible)
    }

    @Test func tapIsIgnoredUnderThePanel() {
        let player = Player()
        let transport = player.controller()
        transport.reveal()
        transport.openPanel()
        transport.toggleDisplay()
        #expect(transport.state.isVisible)
    }

    @Test func playingDisplayArmsTheAutoHide() {
        let player = Player()
        let transport = player.controller()
        transport.toggleDisplay()
        #expect(transport.visibility.deadline == player.clock.addingTimeInterval(OSDVisibility.inactivityDelay))
    }

    @Test func pausedDisplayHasNoDeadline() {
        let player = Player()
        player.isPaused = true
        let transport = player.controller()
        transport.toggleDisplay()
        #expect(transport.visibility.deadline == nil)
    }

    @Test func doubleTapSkipsWithoutOpeningTheDisplay() {
        let player = Player()
        let transport = player.controller()
        transport.skip(.forward, revealsDisplay: false)
        #expect(player.seeks == [110])
        #expect(!transport.state.isVisible)
        #expect(transport.skipFeedback?.direction == .forward)
    }

    @Test func doubleTapKeepsAVisibleDisplayAlive() {
        let player = Player()
        let transport = player.controller()
        transport.reveal()
        player.clock.addTimeInterval(3)
        transport.skip(.backward, revealsDisplay: false)
        #expect(player.seeks == [90])
        #expect(transport.visibility.deadline == player.clock.addingTimeInterval(OSDVisibility.inactivityDelay))
    }

    @Test func dragScrubsWhilePlayingAndSeeksOnRelease() {
        let player = Player()
        let transport = player.controller()
        transport.touchScrub(fraction: 0.5)
        #expect(transport.isScrubbing)
        #expect(transport.displayedPosition == 1500)
        #expect(player.seeks.isEmpty)
        #expect(transport.visibility.isVisible && transport.visibility.deadline == nil)
        transport.touchScrub(fraction: 0.25)
        transport.touchScrubEnded()
        #expect(player.seeks == [750])
        #expect(!transport.isScrubbing)
        #expect(!player.isPaused)
        #expect(transport.visibility.deadline != nil)
    }

    @Test func releasingWhilePausedStaysPaused() {
        let player = Player()
        player.isPaused = true
        let transport = player.controller()
        transport.touchScrub(fraction: 0.1)
        transport.touchScrubEnded()
        #expect(player.seeks == [300])
        #expect(player.isPaused)
        #expect(transport.visibility.isVisible && transport.visibility.deadline == nil)
    }

    @Test func scrubIsRefusedUnderThePanel() {
        let player = Player()
        let transport = player.controller()
        transport.openPanel()
        transport.touchScrub(fraction: 0.5)
        #expect(!transport.isScrubbing)
    }

    @Test func centreButtonDuringScrubCommitsLikeTheRemote() {
        let player = Player()
        let transport = player.controller()
        transport.touchScrub(fraction: 0.5)
        transport.playPause()
        #expect(player.seeks == [1500])
        #expect(!transport.isScrubbing)
    }
}
