import Foundation
import JellyfinAPI

/// The knobs of the device profile. Everything platform- or user-dependent is a parameter, never a
/// compile-time switch (decisions.md, multi-platform): the app passes its own name and the user's bitrate ceiling.
public struct DeviceProfileOptions: Sendable, Equatable {
    /// Maximum streaming and static bitrate, in bits per second (user ceiling, default 120 Mbps).
    public var maxBitrate: Int
    /// `DeviceProfile.Name`, how the server lists this client.
    public var name: String
    /// `false` removes AV1 from DirectPlay so the server transcodes it (4K AV1 has no hardware decode on A15).
    public var allowAV1: Bool

    public init(maxBitrate: Int = 120_000_000, name: String = "Apple TV", allowAV1: Bool = true) {
        self.maxBitrate = maxBitrate
        self.name = name
        self.allowAV1 = allowAV1
    }
}

extension DeviceProfile {
    /// Containers mpv/ffmpeg demux.
    public static let directPlayContainers = ["mkv", "mp4", "m4v", "mov", "avi", "ts", "wmv", "flv", "webm"]
    /// `mpeg2video` and `vp8` go beyond the RN profile (decisions.md: extended DirectPlay).
    public static let directPlayVideoCodecs = ["h264", "hevc", "vp9", "av1", "mpeg4", "vc1", "mpeg2video", "vp8"]
    public static let directPlayAudioCodecs = ["aac", "mp3", "ac3", "eac3", "dts", "truehd", "flac", "opus", "vorbis", "pcm"]

    /// Subtitle codecs as Jellyfin's `NormalizeSubtitleCodec` writes them in `MediaStream.Codec`.
    /// It is `pgssub`, never `pgs`: a wrong string silently kills DirectPlay, with no TranscodeReason.
    public static let embeddedSubtitleFormats = ["subrip", "srt", "ass", "ssa", "pgssub", "dvdsub", "dvbsub", "dvbtxt", "mov_text", "vtt"]
    public static let externalSubtitleFormats = ["srt", "vtt", "ass", "ssa"]

    /// Maximal DirectPlay profile: mpv plays what the server stores, transcoding is the last resort.
    public static func jellyfuse(_ options: DeviceProfileOptions = .init()) -> DeviceProfile {
        let videoCodecs = Self.directPlayVideoCodecs.filter { options.allowAV1 || $0 != "av1" }
        let hdrRanges = "SDR|HDR10|HDR10Plus|HLG|DOVI|DOVIWithHDR10|DOVIWithHDR10Plus|DOVIWithHLG|DOVIWithSDR"

        var codecProfiles = [
            CodecProfile(
                codec: "hevc",
                conditions: [
                    condition(.videoProfile, "main|main 10"),
                    condition(.videoRangeType, hdrRanges),
                ],
                type: .video
            ),
            CodecProfile(
                codec: "h264",
                conditions: [
                    condition(.videoProfile, "high|main|baseline|constrained baseline|high 10"),
                    condition(.videoRangeType, "SDR"),
                ],
                type: .video
            ),
        ]
        if options.allowAV1 {
            codecProfiles.append(CodecProfile(codec: "av1", conditions: [condition(.videoRangeType, hdrRanges)], type: .video))
        }
        codecProfiles.append(CodecProfile(
            conditions: [ProfileCondition(condition: .lessThanEqual, isRequired: false, property: .audioChannels, value: "8")],
            type: .videoAudio
        ))

        return DeviceProfile(
            codecProfiles: codecProfiles,
            directPlayProfiles: [
                DirectPlayProfile(
                    audioCodec: Self.directPlayAudioCodecs.joined(separator: ","),
                    container: Self.directPlayContainers.joined(separator: ","),
                    type: .video, videoCodec: videoCodecs.joined(separator: ",")
                ),
                DirectPlayProfile(container: "mp3,aac,flac,ogg,opus,wav", type: .audio),
            ],
            maxStaticBitrate: options.maxBitrate,
            maxStreamingBitrate: options.maxBitrate,
            name: options.name,
            subtitleProfiles: Self.embeddedSubtitleFormats.map { SubtitleProfile(format: $0, method: .embed) }
                + Self.externalSubtitleFormats.map { SubtitleProfile(format: $0, method: .external) },
            transcodingProfiles: [
                TranscodingProfile(
                    protocol: .hls, audioCodec: "aac", container: "ts", context: .streaming,
                    type: .video, videoCodec: "h264"
                ),
            ]
        )
    }

    private static func condition(_ property: ProfileConditionValue, _ value: String) -> ProfileCondition {
        ProfileCondition(condition: .equalsAny, isRequired: false, property: property, value: value)
    }
}
