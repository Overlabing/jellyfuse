import Foundation
import JellyfinAPI
import LibraryKit
import Testing
@testable import PlaybackEngine

/// Scripted `PlaybackInfoAPI`: records the request body, builds URLs like the server's route shapes.
final class FakeInfoAPI: PlaybackInfoAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [PlaybackInfoDto] = []
    var response = PlaybackInfoResponse()

    var lastBody: PlaybackInfoDto? { lock.withLock { bodies.last } }

    func playbackInfo(itemId: String, body: PlaybackInfoDto) async throws -> PlaybackInfoResponse {
        lock.withLock { bodies.append(body) }
        return response
    }

    func streamURL(itemId: String, mediaSourceId: String, container: String?) -> URL? {
        URL(string: "https://srv/Videos/\(itemId)/stream\(container.map { "." + $0 } ?? "")?Static=true&MediaSourceId=\(mediaSourceId)&api_key=T")
    }

    func serverURL(path: String) -> URL? { URL(string: "https://srv" + path + "&api_key=T") }

    func subtitleURL(itemId: String, mediaSourceId: String, index: Int, format: String) -> URL? {
        URL(string: "https://srv/Videos/\(itemId)/\(mediaSourceId)/Subtitles/\(index)/0/Stream.\(format)?api_key=T")
    }
}

@Suite struct PlaybackResolverTests {
    private let api = FakeInfoAPI()
    private func resolver() -> PlaybackResolver { PlaybackResolver(api: api, profile: .jellyfuse()) }
    private func request(_ overrides: (inout PlaybackRequest) -> Void = { _ in }) -> PlaybackRequest {
        var request = PlaybackRequest(itemId: "item1", userId: "user1")
        overrides(&request)
        return request
    }
    private func respond(_ sources: [MediaSourceInfo], session: String? = "ps1", error: PlaybackErrorCode? = nil) {
        api.response = PlaybackInfoResponse(errorCode: error, mediaSources: sources, playSessionID: session)
    }

    // MARK: Decision tree

    @Test func directPlayUsesTheStaticStreamAndCarriesBothIds() async throws {
        respond([source(id: "srcA", directPlay: true)])
        let resolved = try await resolver().resolve(request())
        #expect(resolved.playMethod == .directPlay)
        #expect(resolved.url.absoluteString == "https://srv/Videos/item1/stream?Static=true&MediaSourceId=srcA&api_key=T")
        #expect(resolved.identity == PlaybackIdentity(itemId: "item1", mediaSourceId: "srcA", playSessionId: "ps1", playMethod: .directPlay))
        #expect(resolved.itemId != resolved.identity.mediaSourceId)
        #expect(resolved.runtimeTicks == 6_000_000_000)
    }

    @Test func directStreamUsesTheContainerRoute() async throws {
        respond([source(id: "srcA", directPlay: false, directStream: true, container: "mp4")])
        let resolved = try await resolver().resolve(request())
        #expect(resolved.playMethod == .directStream)
        #expect(resolved.url.absoluteString.hasPrefix("https://srv/Videos/item1/stream.mp4?"))
    }

    @Test func transcodeUsesTheServerTranscodingUrl() async throws {
        respond([source(directPlay: false, directStream: false, transcodingURL: "/videos/item1/master.m3u8?x=1")])
        let resolved = try await resolver().resolve(request())
        #expect(resolved.playMethod == .transcode)
        #expect(resolved.url.absoluteString == "https://srv/videos/item1/master.m3u8?x=1&api_key=T")
    }

    @Test func directPlayWinsOverTranscodingUrlWhenBothExist() async throws {
        respond([source(directPlay: true, directStream: true, transcodingURL: "/videos/item1/master.m3u8")])
        #expect(try await resolver().resolve(request()).playMethod == .directPlay)
    }

    @Test func noPlayableSourceThrows() async {
        respond([source(directPlay: false, directStream: false, transcodingURL: nil)])
        await #expect(throws: PlaybackError.noPlayableSource) { try await resolver().resolve(request()) }
        respond([])
        await #expect(throws: PlaybackError.noPlayableSource) { try await resolver().resolve(request()) }
    }

    @Test func serverErrorCodeThrows() async {
        respond([source()], error: .noCompatibleStream)
        await #expect(throws: PlaybackError.server(.noCompatibleStream)) { try await resolver().resolve(request()) }
    }

    @Test func chosenVersionWinsOverTheFirstSource() async throws {
        respond([source(id: "first"), source(id: "second")])
        let resolved = try await resolver().resolve(request { $0.mediaSourceId = "second" })
        #expect(resolved.identity.mediaSourceId == "second")
        let defaulted = try await resolver().resolve(request())
        #expect(defaulted.identity.mediaSourceId == "first")
    }

    @Test func requestBodyCarriesProfileUserAndStartTicks() async throws {
        respond([source()])
        _ = try await resolver().resolve(request { $0.startPositionTicks = 123; $0.audioStreamIndex = 2; $0.subtitleStreamIndex = -1 })
        let body = try #require(api.lastBody)
        #expect(body.deviceProfile == DeviceProfile.jellyfuse())
        #expect(body.userID == "user1")
        #expect(body.enableDirectPlay == true && body.enableDirectStream == true && body.enableTranscoding == true)
        #expect(body.isAutoOpenLiveStream == true)
        #expect(body.maxStreamingBitrate == 120_000_000)
        #expect(body.startTimeTicks == 123 && body.audioStreamIndex == 2 && body.subtitleStreamIndex == -1)
    }

    // MARK: Tracks and external subtitles

    private let streams = [
        stream(0, .video, codec: "hevc"),
        stream(1, .audio, codec: "eac3", language: "eng", isDefault: true),
        stream(2, .audio, codec: "aac", language: "fra"),
        stream(3, .subtitle, codec: "pgssub", language: "eng"),
        stream(4, .subtitle, codec: "subrip", language: "fra", isExternal: true),
        stream(5, .subtitle, codec: "ass", language: "eng"),
        stream(6, .subtitle, codec: "pgssub", language: "deu", isExternal: true),
        stream(7, .subtitle, codec: "ass", language: "spa", isExternal: true),
    ]

    @Test func externalSubtitlesExposeStreamUrlsInSubAddOrderAndSkipImageSidecars() async throws {
        respond([source(id: "srcA", streams: streams)])
        let resolved = try await resolver().resolve(request())
        #expect(resolved.externalSubtitles.map(\.index) == [4, 7])
        #expect(resolved.externalSubtitles.map(\.format) == ["srt", "ass"])
        #expect(resolved.externalSubtitles[0].url.absoluteString == "https://srv/Videos/item1/srcA/Subtitles/4/0/Stream.srt?api_key=T")
        #expect(resolved.externalSubtitles[1].url.absoluteString == "https://srv/Videos/item1/srcA/Subtitles/7/0/Stream.ass?api_key=T")
        #expect(resolved.externalSubtitles[0].language == "fra")
    }

    @Test func sidIsGroupAwareForAnExternalSubtitle() async throws {
        respond([source(streams: streams, defaultSubtitle: 4)])
        let resolved = try await resolver().resolve(request())
        // Embedded: 3 -> sid 1, 5 -> sid 2; added externals follow: 4 -> sid 3, 7 -> sid 4.
        #expect(resolved.selection.subtitleIndex == 4 && resolved.selection.subtitleDelivery == .external)
        #expect(resolved.subtitleID == 3)
        #expect(resolved.audioID == 1)
    }

    @Test func sidForAnEmbeddedSubtitleIgnoresTheSidecarInTheMiddle() async throws {
        respond([source(streams: streams, defaultSubtitle: 5)])
        let resolved = try await resolver().resolve(request())
        #expect(resolved.subtitleID == 2)
    }

    @Test func subtitlesOffIsAnExplicitNoSid() async throws {
        respond([source(streams: streams, defaultSubtitle: -1)])
        let resolved = try await resolver().resolve(request())
        #expect(resolved.selection.subtitleIndex == nil && resolved.subtitleID == nil)
    }

    @Test func explicitPickerChoicesBeatThePriorityChain() async throws {
        respond([source(streams: streams, defaultAudio: 1, defaultSubtitle: 3)])
        let resolved = try await resolver().resolve(request { $0.audioStreamIndex = 2; $0.subtitleStreamIndex = 5 })
        #expect(resolved.selection.audioIndex == 2 && resolved.audioID == 2)
        #expect(resolved.selection.subtitleIndex == 5 && resolved.subtitleID == 2)
        let off = try await resolver().resolve(request { $0.subtitleStreamIndex = -1 })
        #expect(off.selection.subtitleIndex == nil && off.subtitleID == nil)
    }

    @Test func transcodeLeavesTracksToTheServer() async throws {
        respond([source(directPlay: false, transcodingURL: "/videos/item1/master.m3u8?a=1", streams: streams, defaultSubtitle: 4)])
        let resolved = try await resolver().resolve(request())
        #expect(resolved.externalSubtitles.isEmpty)
        #expect(resolved.audioID == nil && resolved.subtitleID == nil)
        #expect(resolved.selection.subtitleIndex == 4)
    }

    @Test func descriptionRedactsTheTokenUrl() async throws {
        respond([source()])
        let resolved = try await resolver().resolve(request())
        #expect(!"\(resolved)".contains("api_key"))
        #expect(!String(reflecting: resolved).contains("api_key"))
    }
}

@Suite struct JellyfinClientPlaybackURLTests {
    private let client = LibraryKit.JellyfinClient(
        session: Session(serverURL: URL(string: "https://jelly.example/")!, token: "TOK", userId: "u", userName: "n", deviceId: "d")
    )

    @Test func streamAndSubtitleUrlsUseTheServerRoutesWithApiKey() throws {
        let direct = try #require(client.streamURL(itemId: "i", mediaSourceId: "m", container: nil)?.absoluteString)
        #expect(direct.hasPrefix("https://jelly.example/Videos/i/stream?"))
        #expect(direct.lowercased().contains("static=true") && direct.contains("ApiKey=TOK") && direct.lowercased().contains("mediasourceid=m"))
        let byContainer = try #require(client.streamURL(itemId: "i", mediaSourceId: "m", container: "mp4")?.absoluteString)
        #expect(byContainer.hasPrefix("https://jelly.example/Videos/i/stream.mp4?"))
        let subtitle = try #require(client.subtitleURL(itemId: "i", mediaSourceId: "m", index: 4, format: "srt")?.absoluteString)
        #expect(subtitle.hasPrefix("https://jelly.example/Videos/i/m/Subtitles/4/0/Stream.srt"))
        #expect(subtitle.contains("ApiKey=TOK"))
    }

    @Test func serverPathGetsOneApiKeyOnlyWhenMissing() throws {
        let plain = try #require(client.serverURL(path: "/videos/i/master.m3u8?a=1")?.absoluteString)
        #expect(plain == "https://jelly.example/videos/i/master.m3u8?a=1&ApiKey=TOK")
        let keyed = try #require(client.serverURL(path: "/videos/i/master.m3u8?ApiKey=x&api_key=Y")?.absoluteString)
        #expect(keyed.lowercased().components(separatedBy: "apikey=").count + keyed.lowercased().components(separatedBy: "api_key=").count == 4)
        #expect(!keyed.contains("TOK"))
    }
}
