import Foundation
import JellyfinAPI
import Testing
@testable import PlaybackEngine

@Suite struct MediaSegmentsTests {
    private func dto(_ type: MediaSegmentType, _ start: Int, _ end: Int) -> MediaSegmentDto {
        MediaSegmentDto(endTicks: end * 10_000_000, startTicks: start * 10_000_000, type: type)
    }

    @Test func onlyIntrosAndOutrosWithASpanAreKept() {
        let segments = ItemSegments(dtos: [
            dto(.outro, 1700, 1790), dto(.intro, 30, 90), dto(.recap, 0, 30), dto(.intro, 200, 200),
            MediaSegmentDto(startTicks: 5, type: .intro),
        ])
        #expect(segments.all == [
            MediaSegment(kind: .intro, start: 30, end: 90), MediaSegment(kind: .outro, start: 1700, end: 1790),
        ])
        #expect(segments.credits == MediaSegment(kind: .outro, start: 1700, end: 1790))
    }

    @Test func theIntroIsOfferedInsideItOnly() {
        let segments = ItemSegments(dtos: [dto(.intro, 30, 90)])
        #expect(segments.skippable(at: 29.9, hasNext: true) == nil)
        #expect(segments.skippable(at: 30, hasNext: true)?.end == 90)
        #expect(segments.skippable(at: 89.9, hasNext: true)?.end == 90)
        #expect(segments.skippable(at: 90, hasNext: true) == nil)
    }

    @Test func theCreditsSkipYieldsToTheNextEpisodeCard() {
        let segments = ItemSegments(dtos: [dto(.outro, 1700, 1790)])
        #expect(segments.skippable(at: 1750, hasNext: true) == nil)
        #expect(segments.skippable(at: 1750, hasNext: false)?.kind == .outro)
    }

    @Test func noSegmentsMeansNothingToSkip() {
        #expect(ItemSegments.none.skippable(at: 50, hasNext: false) == nil)
        #expect(ItemSegments.none.credits == nil)
    }
}
