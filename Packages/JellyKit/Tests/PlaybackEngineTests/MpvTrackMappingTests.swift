import JellyfinAPI
import Testing
@testable import PlaybackEngine

@Suite struct MpvTrackMappingTests {
    // Jellyfin lists the sidecar (index 3) between two embedded subtitles; mpv does not.
    private let streams = [
        stream(0, .video),
        stream(1, .audio), stream(2, .audio),
        stream(3, .subtitle, isExternal: true),
        stream(4, .subtitle, codec: "pgssub"),
        stream(5, .subtitle, codec: "subrip"),
        stream(6, .subtitle, isExternal: true),
    ]

    @Test func audioIsAOneBasedPositionAmongAudioStreams() {
        #expect(MpvTrackMapping.audioID(forIndex: 1, streams: streams) == 1)
        #expect(MpvTrackMapping.audioID(forIndex: 2, streams: streams) == 2)
        #expect(MpvTrackMapping.audioID(forIndex: 4, streams: streams) == nil)
        #expect(MpvTrackMapping.audioID(forIndex: nil, streams: streams) == nil)
    }

    @Test func embeddedSubtitlesComeFirstWhateverTheJellyfinOrder() {
        let added = [3, 6]
        #expect(MpvTrackMapping.subtitleID(forIndex: 4, streams: streams, addedExternalIndices: added) == 1)
        #expect(MpvTrackMapping.subtitleID(forIndex: 5, streams: streams, addedExternalIndices: added) == 2)
    }

    @Test func externalsFollowInSubAddOrder() {
        #expect(MpvTrackMapping.subtitleID(forIndex: 3, streams: streams, addedExternalIndices: [3, 6]) == 3)
        #expect(MpvTrackMapping.subtitleID(forIndex: 6, streams: streams, addedExternalIndices: [3, 6]) == 4)
    }

    @Test func aSkippedExternalDoesNotShiftTheOthers() {
        #expect(MpvTrackMapping.subtitleID(forIndex: 6, streams: streams, addedExternalIndices: [6]) == 3)
        #expect(MpvTrackMapping.subtitleID(forIndex: 3, streams: streams, addedExternalIndices: [6]) == nil)
    }

    @Test func offAndUnknownGiveNoSid() {
        #expect(MpvTrackMapping.subtitleID(forIndex: nil, streams: streams, addedExternalIndices: [3]) == nil)
        #expect(MpvTrackMapping.subtitleID(forIndex: 99, streams: streams, addedExternalIndices: [3]) == nil)
    }
}
