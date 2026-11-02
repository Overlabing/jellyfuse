import Testing
@testable import DesignSystem

@Suite struct ChapterMarksTests {
    @Test func marksAreFractionsWithoutTheStart() {
        let marks = ChapterMarks.fractions(starts: [0, 600, 1800, 3000], duration: 3000)
        // 0 is the start and 3000 is the end: neither is drawn.
        #expect(marks == [0.2, 0.6])
    }

    @Test func noDurationNoMarks() {
        #expect(ChapterMarks.fractions(starts: [0, 600], duration: 0).isEmpty)
        #expect(ChapterMarks.fractions(starts: [600], duration: .nan).isEmpty)
    }

    @Test func currentChapterIsTheLastStarted() {
        let starts = [0.0, 600, 1800]
        #expect(ChapterMarks.currentIndex(starts: starts, position: 0) == 0)
        #expect(ChapterMarks.currentIndex(starts: starts, position: 1799) == 1)
        #expect(ChapterMarks.currentIndex(starts: starts, position: 1800) == 2)
        #expect(ChapterMarks.currentIndex(starts: [60], position: 10) == nil)
        #expect(ChapterMarks.currentIndex(starts: [], position: 10) == nil)
    }

    @Test func chapterRowsAreNamedTimedAndMarked() {
        let rows = ChapterRow.rows(names: ["Intro", nil, ""], starts: [0, 65, 3700], position: 100)
        #expect(rows.map(\.title) == ["Intro", "Chapitre 2", "Chapitre 3"])
        #expect(rows.map(\.time) == ["0:00:00", "0:01:05", "1:01:40"])
        #expect(rows.map(\.isCurrent) == [false, true, false])
        #expect(rows[2].startSeconds == 3700)
    }
}

@Suite struct ContentTabsModelTests {
    private func model(audio: [TrackRow] = [], subtitles: [TrackRow] = [], chapters: [ChapterRow] = []) -> ContentTabsModel {
        ContentTabsModel(info: InfoContent(title: "T"), audio: audio, subtitles: subtitles, chapters: chapters, canSwitchTracks: true)
    }

    @Test func subtitleListStartsWithOffChecked() {
        let list = TrackRow.subtitleList([TrackRow(id: 4, title: "Français", isSelected: false)])
        #expect(list.map(\.id) == [TrackRow.offID, 4])
        #expect(list.map(\.isSelected) == [true, false])
    }

    @Test func offIsUncheckedWhenATrackIs() {
        let list = TrackRow.subtitleList([TrackRow(id: 4, title: "Français", isSelected: true)])
        #expect(list.map(\.isSelected) == [false, true])
    }

    @Test func tabsHideWhenEmpty() {
        #expect(model().tabs == [.info])
        let full = model(
            audio: [TrackRow(id: 1, title: "A", isSelected: true)], subtitles: [TrackRow(id: 2, title: "S", isSelected: false)],
            chapters: [ChapterRow(id: 0, title: "C", time: "0:00:00", startSeconds: 0, isCurrent: true)]
        )
        #expect(full.tabs == [.info, .audio, .subtitles, .chapters])
    }
}

@MainActor @Suite struct ContentPanelTests {
    private func controller(paused: Bool = false) -> (TransportController, () -> Bool) {
        var isPaused = paused
        let transport = TransportController(driver: .init(
            position: { 100 }, duration: { 3000 }, isPaused: { isPaused }, seek: { _ in }, setPaused: { isPaused = $0 }
        ))
        return (transport, { isPaused })
    }

    @Test func downOpensThePanelAndHoldsTheDisplay() {
        let (transport, _) = controller()
        transport.openPanel()
        #expect(transport.isPanelOpen)
        #expect(transport.state.isVisible)
        #expect(transport.visibility.deadline == nil)
    }

    @Test func menuClosesThePanelBeforeLeavingThePlayer() {
        let (transport, _) = controller()
        transport.openPanel()
        #expect(transport.menu() == .handled)
        #expect(!transport.isPanelOpen)
        // The display is still up (timer armed); the next Menu hides it, then the next leaves.
        #expect(transport.state.isVisible)
        #expect(transport.visibility.deadline != nil)
        #expect(transport.menu() == .handled)
        #expect(transport.menu() == .exit)
    }

    @Test func closingWhilePausedKeepsTheDisplay() {
        let (transport, _) = controller(paused: true)
        transport.openPanel()
        transport.closePanel()
        #expect(transport.state.isVisible)
        #expect(transport.visibility.deadline == nil)
    }

    @Test func theTimerCannotHideTheDisplayUnderTheOpenPanel() {
        let (transport, _) = controller()
        transport.openPanel()
        transport.reveal()
        transport.pausedChanged(false)
        transport.expire()
        #expect(transport.state.isVisible)
        #expect(transport.visibility.deadline == nil)
    }

    @Test func downDoesNothingWhileScrubbing() {
        let (transport, _) = controller(paused: true)
        transport.panBegan()
        transport.openPanel()
        #expect(!transport.isPanelOpen)
        #expect(transport.isScrubbing)
    }
}

@Suite struct SegmentedBarTests {
    @Test func segmentsSplitAtTheMarks() {
        #expect(ChapterMarks.segments(marks: [0.2, 0.6]) == [0...0.2, 0.2...0.6, 0.6...1])
        #expect(ChapterMarks.segments(marks: []) == [0...1])
    }

    @Test func widthsLeaveRoomForTheGaps() {
        let segments = ChapterMarks.segments(marks: [0.5])
        let widths = ChapterMarks.segmentWidths(segments, width: 1006, gap: 6)
        #expect(widths == [500, 500])
    }

    @Test func playheadSkipsTheGapsBeforeItsSegment() {
        let segments = ChapterMarks.segments(marks: [0.5])
        // 1006 wide, 6 gap: segments are 500 each; the second starts at 506.
        #expect(ChapterMarks.playheadX(progress: 0.25, segments: segments, width: 1006, gap: 6) == 250)
        #expect(ChapterMarks.playheadX(progress: 0.75, segments: segments, width: 1006, gap: 6) == 756)
        #expect(ChapterMarks.playheadX(progress: 1, segments: segments, width: 1006, gap: 6) == 1006)
        #expect(ChapterMarks.playheadX(progress: 0, segments: segments, width: 1006, gap: 6) == 0)
    }
}
