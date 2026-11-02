import Foundation
import JellyfinAPI
import LibraryKit

/// An intro or the closing credits of an item (Jellyfin 10.10+ `MediaSegment`), in seconds.
public struct MediaSegment: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case intro
        case outro
    }

    public let kind: Kind
    public let start: Double
    public let end: Double

    public init(kind: Kind, start: Double, end: Double) {
        self.kind = kind
        self.start = start
        self.end = end
    }

    /// Start inclusive, end exclusive.
    public func contains(_ position: Double) -> Bool {
        position >= start && position < end
    }
}

/// The segments the server knows for one item.
public struct ItemSegments: Sendable, Equatable {
    public let all: [MediaSegment]

    public static let none = ItemSegments(all: [])

    public init(all: [MediaSegment]) {
        self.all = all
    }

    /// Intros and outros with a start and an end that make a span, earliest first.
    init(dtos: [MediaSegmentDto]) {
        let ticks = Double(PlaybackSnapshot.ticksPerSecond)
        all = dtos.compactMap { dto -> MediaSegment? in
            guard let startTicks = dto.startTicks, let endTicks = dto.endTicks, endTicks > startTicks else { return nil }
            let kind: MediaSegment.Kind
            switch dto.type {
            case .intro: kind = .intro
            case .outro: kind = .outro
            default: return nil
            }
            return MediaSegment(kind: kind, start: Double(startTicks) / ticks, end: Double(endTicks) / ticks)
        }
        .sorted { $0.start < $1.start }
    }

    /// The closing credits, for the end-of-episode gate.
    public var credits: MediaSegment? { all.first { $0.kind == .outro } }

    /// The segment « Passer… » offers at `position`: the intro; the credits only when no next episode takes
    /// them over (the end-of-episode card then does).
    public func skippable(at position: Double, hasNext: Bool) -> MediaSegment? {
        all.first { $0.contains(position) && ($0.kind == .intro || !hasNext) }
    }
}

/// What the player needs from the network besides the stream: the segments and the trickplay tiles.
public protocol PlayerExtrasAPI: Sendable {
    /// One request per playback. Servers before 10.10 have no such route: callers treat a failure as « none ».
    func segments(itemId: String) async throws -> ItemSegments
    /// `/Videos/{id}/Trickplay/{width}/{index}.jpg`, carrying `api_key`: never log it.
    func trickplayTileURL(itemId: String, width: Int, index: Int) -> URL?
}

extension LibraryKit.JellyfinClient: PlayerExtrasAPI {
    public func segments(itemId: String) async throws -> ItemSegments {
        let result = try await perform(Paths.getItemSegments(itemID: itemId, includeSegmentTypes: [.intro, .outro]))
        return ItemSegments(dtos: result.items ?? [])
    }

    public nonisolated func trickplayTileURL(itemId: String, width: Int, index: Int) -> URL? {
        authenticatedURL(for: Paths.getTrickplayTileImage(itemID: itemId, width: width, index: index))
    }
}
