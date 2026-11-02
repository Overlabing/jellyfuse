import Foundation
import JellyfinAPI
@testable import PlaybackEngine

func stream(
    _ index: Int, _ type: MediaStreamType, codec: String? = nil, language: String? = nil,
    isDefault: Bool = false, isForced: Bool = false, isExternal: Bool = false
) -> MediaStream {
    var s = MediaStream()
    s.index = index
    s.type = type
    s.codec = codec
    s.language = language
    s.isDefault = isDefault
    s.isForced = isForced
    s.isExternal = isExternal
    return s
}

func source(
    id: String = "src1", directPlay: Bool = true, directStream: Bool = false, transcodingURL: String? = nil,
    container: String? = "mkv", streams: [MediaStream] = [], defaultAudio: Int? = nil, defaultSubtitle: Int? = nil,
    runtime: Int = 6_000_000_000
) -> MediaSourceInfo {
    var s = MediaSourceInfo()
    s.id = id
    s.container = container
    s.isSupportsDirectPlay = directPlay
    s.isSupportsDirectStream = directStream
    s.transcodingURL = transcodingURL
    s.mediaStreams = streams
    s.defaultAudioStreamIndex = defaultAudio
    s.defaultSubtitleStreamIndex = defaultSubtitle
    s.runTimeTicks = runtime
    return s
}
