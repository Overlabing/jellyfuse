import Foundation
import JellyfinAPI
import LibraryKit

/// What the resolver needs from the network. `JellyfinClient` is the real one; tests inject a fake.
public protocol PlaybackInfoAPI: Sendable {
    func playbackInfo(itemId: String, body: PlaybackInfoDto) async throws -> PlaybackInfoResponse
    /// Direct file URL (`Static=true`), by container when given (DirectStream). Carries `api_key`.
    func streamURL(itemId: String, mediaSourceId: String, container: String?) -> URL?
    /// A server-relative path (e.g. a `TranscodingUrl`) as an absolute URL carrying `api_key`.
    func serverURL(path: String) -> URL?
    /// `/Videos/{id}/{ms}/Subtitles/{index}/0/Stream.{format}`, carrying `api_key`.
    func subtitleURL(itemId: String, mediaSourceId: String, index: Int, format: String) -> URL?
}

extension LibraryKit.JellyfinClient: PlaybackInfoAPI {
    public func playbackInfo(itemId: String, body: PlaybackInfoDto) async throws -> PlaybackInfoResponse {
        try await perform(Paths.getPostedPlaybackInfo(itemID: itemId, body))
    }

    public nonisolated func streamURL(itemId: String, mediaSourceId: String, container: String?) -> URL? {
        if let container {
            return authenticatedURL(for: Paths.getVideoStreamByContainer(
                itemID: itemId, container: container, parameters: .init(isStatic: true, mediaSourceID: mediaSourceId)
            ))
        }
        return authenticatedURL(for: Paths.getVideoStream(
            itemID: itemId, parameters: .init(isStatic: true, mediaSourceID: mediaSourceId)
        ))
    }

    public nonisolated func serverURL(path: String) -> URL? {
        authenticatedURL(path: path)
    }

    public nonisolated func subtitleURL(itemId: String, mediaSourceId: String, index: Int, format: String) -> URL? {
        authenticatedURL(for: Paths.getSubtitleWithTicks(
            routeItemID: itemId, routeMediaSourceID: mediaSourceId, routeIndex: index,
            routeStartPositionTicks: 0, routeFormat: format
        ))
    }
}
