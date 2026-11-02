import Foundation
import JellyfinAPI
import Testing
@testable import PlaybackEngine

@Suite struct DeviceProfileTests {
    private let profile = DeviceProfile.jellyfuse()

    @Test func subtitleProfilesUseCanonicalJellyfinStrings() {
        let embedded = Set(profile.subtitleProfiles?.filter { $0.method == .embed }.compactMap(\.format) ?? [])
        let external = Set(profile.subtitleProfiles?.filter { $0.method == .external }.compactMap(\.format) ?? [])
        #expect(embedded == ["subrip", "srt", "ass", "ssa", "pgssub", "dvdsub", "dvbsub", "dvbtxt", "mov_text", "vtt"])
        #expect(external == ["srt", "vtt", "ass", "ssa"])
        #expect(embedded.contains("pgssub"))
        #expect(!embedded.contains("pgs") && !external.contains("pgs"))
        #expect(!embedded.contains("PGSSUB"))
    }

    @Test func serializedProfileNeverCarriesAWrongPgsString() throws {
        let json = try String(decoding: JSONEncoder().encode(profile), as: UTF8.self)
        #expect(json.contains("\"pgssub\""))
        #expect(!json.contains("\"pgs\""))
    }

    @Test func directPlayCoversEveryMpvCodecIncludingMpeg2AndVp8() throws {
        let video = try #require(profile.directPlayProfiles?.first { $0.type == .video })
        let codecs = Set((video.videoCodec ?? "").split(separator: ",").map(String.init))
        #expect(codecs == ["h264", "hevc", "vp9", "av1", "mpeg4", "vc1", "mpeg2video", "vp8"])
        let audio = Set((video.audioCodec ?? "").split(separator: ",").map(String.init))
        #expect(audio == ["aac", "mp3", "ac3", "eac3", "dts", "truehd", "flac", "opus", "vorbis", "pcm"])
        let containers = Set((video.container ?? "").split(separator: ",").map(String.init))
        #expect(containers == ["mkv", "mp4", "m4v", "mov", "avi", "ts", "wmv", "flv", "webm"])
    }

    @Test func codecProfilesAreAllOptional() throws {
        let conditions = (profile.codecProfiles ?? []).flatMap { $0.conditions ?? [] }
        #expect(!conditions.isEmpty)
        #expect(conditions.allSatisfy { $0.isRequired == false })
        let hevc = try #require(profile.codecProfiles?.first { $0.codec == "hevc" })
        let ranges = try #require(hevc.conditions?.first { $0.property == .videoRangeType }?.value)
        #expect(ranges.split(separator: "|").contains("DOVIWithHDR10Plus"))
        let h264 = try #require(profile.codecProfiles?.first { $0.codec == "h264" })
        #expect(h264.conditions?.first { $0.property == .videoRangeType }?.value == "SDR")
        let channels = try #require(profile.codecProfiles?.first { $0.type == .videoAudio })
        #expect(channels.conditions?.first?.value == "8")
    }

    @Test func bitrateAndNameAreParameters() {
        let custom = DeviceProfile.jellyfuse(.init(maxBitrate: 40_000_000, name: "Living room"))
        #expect(custom.maxStreamingBitrate == 40_000_000)
        #expect(custom.maxStaticBitrate == 40_000_000)
        #expect(custom.name == "Living room")
        #expect(profile.maxStreamingBitrate == 120_000_000)
        #expect(profile.name == "Apple TV")
    }

    @Test func profileWithoutAV1LetsTheServerTranscodeIt() {
        let noAV1 = DeviceProfile.jellyfuse(.init(allowAV1: false))
        let video = noAV1.directPlayProfiles?.first { $0.type == .video }
        let codecs = (video?.videoCodec ?? "").split(separator: ",").map(String.init)
        #expect(!codecs.contains("av1"))
        #expect(codecs.contains("hevc"))
        #expect(noAV1.codecProfiles?.contains { $0.codec == "av1" } == false)
    }

    @Test func transcodingIsTheHlsLastResort() throws {
        let transcoding = try #require(profile.transcodingProfiles?.first)
        #expect(transcoding.container == "ts" && transcoding.videoCodec == "h264" && transcoding.audioCodec == "aac")
        #expect(transcoding.protocol == .hls)
    }
}
