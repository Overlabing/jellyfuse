import Foundation
import JellyfinAPI

public enum PlaybackError: Error, Equatable, Sendable {
    /// The server refused (`NotAllowed`, `NoCompatibleStream`, `RateLimitExceeded`).
    case server(PlaybackErrorCode)
    /// No source can be played: no DirectPlay, DirectStream nor transcoding URL.
    case noPlayableSource
    case urlUnavailable
}

/// What to play and how the user chose to play it.
public struct PlaybackRequest: Sendable, Equatable {
    public var itemId: String
    public var userId: String
    /// A version the user picked; nil = the server's first source.
    public var mediaSourceId: String?
    /// Explicit track choices (from the track picker); nil = run the priority chain.
    public var audioStreamIndex: Int?
    public var subtitleStreamIndex: Int?
    public var startPositionTicks: Int64
    public var tracks: TrackSelectionInput

    public init(
        itemId: String, userId: String, mediaSourceId: String? = nil,
        audioStreamIndex: Int? = nil, subtitleStreamIndex: Int? = nil,
        startPositionTicks: Int64 = 0, tracks: TrackSelectionInput = .init()
    ) {
        self.itemId = itemId
        self.userId = userId
        self.mediaSourceId = mediaSourceId
        self.audioStreamIndex = audioStreamIndex
        self.subtitleStreamIndex = subtitleStreamIndex
        self.startPositionTicks = startPositionTicks
        self.tracks = tracks
    }
}

/// The identity of one playback as the server knows it. `itemId` and `mediaSourceId` are two different
/// ids: reports must carry the item's id in `ItemId` (the RN client once sent the source's).
public struct PlaybackIdentity: Sendable, Equatable, Codable {
    public let itemId: String
    public let mediaSourceId: String
    public let playSessionId: String
    public let playMethod: PlayMethod

    public init(itemId: String, mediaSourceId: String, playSessionId: String, playMethod: PlayMethod) {
        self.itemId = itemId
        self.mediaSourceId = mediaSourceId
        self.playSessionId = playSessionId
        self.playMethod = playMethod
    }
}

/// A sidecar subtitle: not in the static stream, so mpv must `sub-add` it from `url`.
public struct ExternalSubtitle: Sendable, Equatable {
    /// Jellyfin stream index.
    public let index: Int
    public let url: URL
    /// `srt`, `ass`, `ssa` or `vtt`.
    public let format: String
    public let language: String?
    public let title: String?
    public let isForced: Bool
    public let isDefault: Bool
}

/// The outcome of resolving an item: a URL for mpv and everything the player and reporter need.
///
/// `url` and the subtitle URLs carry the user's `api_key` (mpv cannot set headers): never log nor persist them.
public struct ResolvedPlayback: Sendable, Equatable {
    public let identity: PlaybackIdentity
    public let url: URL
    public let container: String?
    public let runtimeTicks: Int64?
    public let startPositionTicks: Int64
    /// Jellyfin stream indexes of the tracks chosen.
    public let selection: TrackSelection
    /// mpv `aid` / `sid` of those tracks; nil `subtitleID` means `sid=no`, to be set explicitly at load.
    /// Both nil when transcoding: the server already applied the choice to the stream it sends.
    public let audioID: Int?
    public let subtitleID: Int?
    /// To `sub-add` in this order, before any `sid` is set. Empty when transcoding.
    public let externalSubtitles: [ExternalSubtitle]
    /// Every stream of the chosen source, for the track pickers.
    public let streams: [MediaStream]

    public var itemId: String { identity.itemId }
    public var playMethod: PlayMethod { identity.playMethod }
}

extension ResolvedPlayback: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "ResolvedPlayback(item: \(identity.itemId), method: \(identity.playMethod.rawValue), url: <redacted>)"
    }
    public var debugDescription: String { description }
}

/// Turns an item into a playable URL: `POST /Items/{id}/PlaybackInfo` then the tree of data-plan §6.4.
/// No cache: `PlaybackInfo` is never reused (staleTime 0).
public struct PlaybackResolver: Sendable {
    private let api: any PlaybackInfoAPI
    private let profile: DeviceProfile

    /// The profile is a parameter, not a constant (e.g. a variant without AV1).
    public init(api: any PlaybackInfoAPI, profile: DeviceProfile) {
        self.api = api
        self.profile = profile
    }

    public func resolve(_ request: PlaybackRequest) async throws -> ResolvedPlayback {
        let body = PlaybackInfoDto(
            audioStreamIndex: request.audioStreamIndex,
            deviceProfile: profile,
            enableDirectPlay: true, enableDirectStream: true, enableTranscoding: true,
            isAutoOpenLiveStream: true,
            maxStreamingBitrate: profile.maxStreamingBitrate,
            mediaSourceID: request.mediaSourceId,
            startTimeTicks: request.startPositionTicks > 0 ? Int(request.startPositionTicks) : nil,
            subtitleStreamIndex: request.subtitleStreamIndex,
            userID: request.userId
        )
        let response = try await api.playbackInfo(itemId: request.itemId, body: body)
        return try Self.decide(response, request: request, api: api)
    }

    /// The decision tree, pure given the response.
    static func decide(_ response: PlaybackInfoResponse, request: PlaybackRequest, api: any PlaybackInfoAPI) throws -> ResolvedPlayback {
        if let code = response.errorCode { throw PlaybackError.server(code) }
        let sources = response.mediaSources ?? []
        guard let source = sources.first(where: { $0.id == request.mediaSourceId }) ?? sources.first,
              let sourceId = source.id else { throw PlaybackError.noPlayableSource }

        let method: PlayMethod
        let url: URL?
        if source.isSupportsDirectPlay == true {
            method = .directPlay
            url = api.streamURL(itemId: request.itemId, mediaSourceId: sourceId, container: nil)
        } else if source.isSupportsDirectStream == true {
            method = .directStream
            url = api.streamURL(itemId: request.itemId, mediaSourceId: sourceId, container: source.container)
        } else if let path = source.transcodingURL {
            method = .transcode
            url = api.serverURL(path: path)
        } else {
            throw PlaybackError.noPlayableSource
        }
        guard let url else { throw PlaybackError.urlUnavailable }

        var selection = TrackSelection.choose(from: source, input: request.tracks)
        applyExplicitChoices(request, source: source, to: &selection)

        let streams = source.mediaStreams ?? []
        var externals: [ExternalSubtitle] = []
        var audioID: Int?
        var subtitleID: Int?
        if method != .transcode {
            externals = externalSubtitles(of: source, sourceId: sourceId, itemId: request.itemId, api: api)
            audioID = MpvTrackMapping.audioID(forIndex: selection.audioIndex, streams: streams)
            subtitleID = MpvTrackMapping.subtitleID(
                forIndex: selection.subtitleIndex, streams: streams, addedExternalIndices: externals.map(\.index)
            )
        }

        return ResolvedPlayback(
            identity: PlaybackIdentity(
                itemId: request.itemId, mediaSourceId: sourceId,
                playSessionId: response.playSessionID ?? "", playMethod: method
            ),
            url: url, container: source.container,
            runtimeTicks: source.runTimeTicks.map(Int64.init),
            startPositionTicks: request.startPositionTicks,
            selection: selection, audioID: audioID, subtitleID: subtitleID, externalSubtitles: externals,
            streams: streams
        )
    }

    /// Indexes the user picked in the track picker win over the priority chain; -1 turns subtitles off.
    private static func applyExplicitChoices(_ request: PlaybackRequest, source: MediaSourceInfo, to selection: inout TrackSelection) {
        if let audio = request.audioStreamIndex { selection.audioIndex = audio }
        guard let subtitle = request.subtitleStreamIndex else { return }
        if subtitle < 0 {
            selection.subtitleIndex = nil
            selection.subtitleDelivery = nil
        } else {
            let stream = source.mediaStreams?.first { $0.index == subtitle && $0.type == .subtitle }
            selection.subtitleIndex = subtitle
            selection.subtitleDelivery = stream?.isExternal == true ? .external : .embed
        }
    }

    /// Text sidecar subtitles, by stream index. Image-based sidecars cannot be fetched as a text format
    /// and are skipped; the mapping accounts only for what is added.
    private static func externalSubtitles(of source: MediaSourceInfo, sourceId: String, itemId: String, api: any PlaybackInfoAPI) -> [ExternalSubtitle] {
        let sidecars = (source.mediaStreams ?? [])
            .filter { $0.type == .subtitle && $0.isExternal == true }
            .sorted { ($0.index ?? 0) < ($1.index ?? 0) }
        return sidecars.compactMap { stream in
            guard let index = stream.index, let format = externalFormat(codec: stream.codec),
                  let url = api.subtitleURL(itemId: itemId, mediaSourceId: sourceId, index: index, format: format) else { return nil }
            return ExternalSubtitle(
                index: index, url: url, format: format, language: stream.language,
                title: stream.displayTitle ?? stream.title,
                isForced: stream.isForced == true, isDefault: stream.isDefault == true
            )
        }
    }

    /// The extension of the text format the server serves for a sidecar codec.
    static func externalFormat(codec: String?) -> String? {
        switch codec?.lowercased() {
        case "srt", "subrip": "srt"
        case "ass": "ass"
        case "ssa": "ssa"
        case "vtt", "webvtt": "vtt"
        default: nil
        }
    }
}
