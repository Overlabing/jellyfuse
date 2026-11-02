import DesignSystem
import Foundation
import LibraryKit

/// What the player needs to start an item: Jellyfin ids double as the single media source id.
public struct PlayTarget: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    /// Where to resume; 0 starts from the beginning.
    public let resumeSeconds: Double

    public init(id: String, title: String, resumeSeconds: Double) {
        self.id = id
        self.title = title
        self.resumeSeconds = resumeSeconds
    }
}

/// The home billboard with what its buttons need.
public struct BillboardContent: Sendable, Equatable {
    public let model: BillboardModel
    public let target: PlayTarget
    /// `Reprendre` when there is progress, `Lecture` otherwise.
    public let primaryLabel: String
}

/// Everything the home screen shows, as display values.
public struct HomeContent: Sendable, Equatable {
    public let billboard: BillboardContent?
    public let upNext: [LandscapeModel]
    public let recent: [PosterModel]
    private let targets: [String: PlayTarget]

    public var isEmpty: Bool { billboard == nil && upNext.isEmpty && recent.isEmpty }

    init(billboard: BillboardContent?, upNext: [LandscapeModel], recent: [PosterModel], targets: [String: PlayTarget]) {
        self.billboard = billboard
        self.upNext = upNext
        self.recent = recent
        self.targets = targets
    }

    public func target(for id: String) -> PlayTarget? { targets[id] }
}

/// Pure mapping from `LibraryKit` entries to `DesignSystem` display models (ui-plan §6.2).
public enum HomeMapper {
    /// `(itemId, imageTag, maxWidth)` -> image URL; the app passes `JellyfinClient.imageURL`.
    public typealias ImageURL = @Sendable (_ itemId: String, _ tag: String?, _ maxWidth: Int) -> URL?

    public static let billboardImageWidth = 1920
    public static let landscapeImageWidth = 800
    public static let posterImageWidth = 500

    private static let ticksPerSecond = 10_000_000.0

    /// « À suivre »: resumes first, then next episodes, one entry per id and per series.
    public static func upNextEntries(continueWatching: [LibraryEntry], nextUp: [LibraryEntry]) -> [LibraryEntry] {
        var seenIds = Set<String>()
        var seenSeries = Set<String>()
        var result: [LibraryEntry] = []
        for entry in continueWatching + nextUp {
            guard seenIds.insert(entry.item.id).inserted else { continue }
            if let series = entry.item.seriesName, !seenSeries.insert(series).inserted { continue }
            result.append(entry)
        }
        return result
    }

    public static func content(
        continueWatching: [LibraryEntry],
        nextUp: [LibraryEntry],
        recentlyAdded: [LibraryEntry],
        imageURL: ImageURL
    ) -> HomeContent {
        let upNext = upNextEntries(continueWatching: continueWatching, nextUp: nextUp)
        var targets: [String: PlayTarget] = [:]
        for entry in upNext + recentlyAdded { targets[entry.item.id] = target(for: entry) }

        let billboard = (upNext.first ?? recentlyAdded.first).map { entry in
            let target = target(for: entry)
            return BillboardContent(
                model: billboard(entry, imageURL: imageURL),
                target: target,
                primaryLabel: target.resumeSeconds > 0 ? String(localized: "Reprendre") : String(localized: "Lecture")
            )
        }
        return HomeContent(
            billboard: billboard,
            upNext: upNext.map { landscape($0, imageURL: imageURL) },
            recent: recentlyAdded.map { poster($0, imageURL: imageURL) },
            targets: targets
        )
    }

    // MARK: Single entries

    public static func target(for entry: LibraryEntry) -> PlayTarget {
        let resume = entry.userData.played ? 0 : Double(entry.userData.playbackPositionTicks) / ticksPerSecond
        return PlayTarget(id: entry.item.id, title: displayTitle(entry.item), resumeSeconds: resume)
    }

    static func displayTitle(_ item: MediaItem) -> String {
        item.seriesName ?? item.name
    }

    static func billboard(_ entry: LibraryEntry, imageURL: ImageURL) -> BillboardModel {
        let item = entry.item
        let title = displayTitle(item)
        return BillboardModel(
            id: item.id,
            title: title,
            // The store carries no synopsis yet: an episode shows its own name, a movie nothing.
            overview: item.seriesName == nil ? "" : item.name,
            backdrop: ArtworkSource(url: imageURL(item.id, item.primaryImageTag, billboardImageWidth), placeholderTitle: title),
            runtimeMinutes: item.runtimeTicks.map { Int($0 / 600_000_000) }
        )
    }

    static func landscape(_ entry: LibraryEntry, imageURL: ImageURL) -> LandscapeModel {
        let item = entry.item
        let title = displayTitle(item)
        let remaining = remainingText(entry)
        let subtitle = [item.seriesName == nil ? nil : item.name, remaining].compactMap { $0 }.joined(separator: " · ")
        return LandscapeModel(
            id: item.id,
            title: title,
            subtitle: subtitle.isEmpty ? nil : subtitle,
            image: ArtworkSource(url: imageURL(item.id, item.primaryImageTag, landscapeImageWidth), placeholderTitle: title),
            progress: entry.userData.progress(runtimeTicks: item.runtimeTicks)
        )
    }

    static func poster(_ entry: LibraryEntry, imageURL: ImageURL) -> PosterModel {
        let item = entry.item
        let title = displayTitle(item)
        return PosterModel(
            id: item.id,
            title: title,
            subtitle: item.seriesName == nil ? nil : item.name,
            image: ArtworkSource(url: imageURL(item.id, item.primaryImageTag, posterImageWidth), placeholderTitle: title),
            isWatched: entry.userData.played
        )
    }

    private static func remainingText(_ entry: LibraryEntry) -> String? {
        guard let runtime = entry.item.runtimeTicks, entry.userData.playbackPositionTicks > 0, !entry.userData.played else { return nil }
        return MediaFormat.remaining(seconds: Double(runtime - entry.userData.playbackPositionTicks) / ticksPerSecond)
    }
}
