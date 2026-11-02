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
    /// The movie or series whose detail screen the billboard opens; nil for an episode of an unknown series.
    public let detailId: String?
    /// `Reprendre` when there is progress, `Lecture` otherwise.
    public let primaryLabel: String

    /// What « Ma liste » acts on: the detail target (the series for an episode), else the item itself.
    public var listId: String { detailId ?? model.id }
}

/// A library as the home screen needs it: the library, and its « Ajouts récents » posters.
public struct LibraryShelfSource: Sendable, Equatable {
    public let library: Library
    public let entries: [LibraryEntry]

    public init(library: Library, entries: [LibraryEntry]) {
        self.library = library
        self.entries = entries
    }
}

/// One « Ajouts récents » shelf of a library. It is empty until that library's first load answers.
public struct LibraryShelfContent: Sendable, Equatable, Identifiable {
    public var id: String { library.id }
    public let library: Library
    /// `Films — Ajouts récents`.
    public let title: String
    public let items: [PosterModel]
}

/// Everything the home screen shows, as display values.
public struct HomeContent: Sendable, Equatable {
    public let billboard: BillboardContent?
    public let upNext: [LandscapeModel]
    /// One per video library, in the server's order.
    public let libraryShelves: [LibraryShelfContent]
    private let targets: [String: PlayTarget]

    public var isEmpty: Bool { billboard == nil && upNext.isEmpty && libraryShelves.allSatisfy { $0.items.isEmpty } }

    init(billboard: BillboardContent?, upNext: [LandscapeModel], libraryShelves: [LibraryShelfContent], targets: [String: PlayTarget]) {
        self.billboard = billboard
        self.upNext = upNext
        self.libraryShelves = libraryShelves
        self.targets = targets
    }

    public func target(for id: String) -> PlayTarget? { targets[id] }
}

/// The « Voir tout » grid of one library.
public struct LibraryGridContent: Sendable, Equatable {
    public let title: String
    public let items: [PosterModel]

    public var isEmpty: Bool { items.isEmpty }

    init(title: String, items: [PosterModel]) {
        self.title = title
        self.items = items
    }
}

/// Pure mapping from `LibraryKit` entries to `DesignSystem` display models (ui-plan §6.2).
public enum HomeMapper {
    /// `(itemId, imageTag, maxWidth)` -> image URL; the app passes `JellyfinClient.imageURL`.
    public typealias ImageURL = @Sendable (_ itemId: String, _ kind: ItemImageKind, _ tag: String?, _ maxWidth: Int) -> URL?

    public static let billboardImageWidth = 1920
    public static let logoImageWidth = DetailMapper.logoImageWidth
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
        libraries: [LibraryShelfSource],
        isInList: (String) -> Bool = { _ in false },
        imageURL: ImageURL
    ) -> HomeContent {
        let upNext = upNextEntries(continueWatching: continueWatching, nextUp: nextUp)
        var targets: [String: PlayTarget] = [:]
        for entry in upNext + libraries.flatMap(\.entries) { targets[entry.item.id] = target(for: entry) }

        let billboard = (upNext.first ?? libraries.lazy.compactMap(\.entries.first).first).map { entry in
            let target = target(for: entry)
            let detailId = entry.item.kind == .episode ? entry.item.seriesId : entry.item.id
            return BillboardContent(
                model: billboard(entry, isInList: isInList(detailId ?? entry.item.id), imageURL: imageURL),
                target: target,
                detailId: detailId,
                primaryLabel: target.resumeSeconds > 0 ? String(localized: "Reprendre", bundle: .module) : String(localized: "Lecture", bundle: .module)
            )
        }
        return HomeContent(
            billboard: billboard,
            upNext: upNext.map { landscape($0, imageURL: imageURL) },
            libraryShelves: libraries.map { source in
                LibraryShelfContent(
                    library: source.library,
                    title: String(localized: "\(source.library.name) — Ajouts récents", bundle: .module),
                    items: source.entries.map { poster($0, imageURL: imageURL) }
                )
            },
            targets: targets
        )
    }

    /// The « Voir tout » grid: every entry of the library, in the order given (newest added first).
    public static func grid(library: Library, entries: [LibraryEntry], imageURL: ImageURL) -> LibraryGridContent {
        LibraryGridContent(
            title: library.name,
            items: entries.map { poster($0, imageURL: imageURL) }
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

    static func billboard(_ entry: LibraryEntry, isInList: Bool, imageURL: ImageURL) -> BillboardModel {
        let item = entry.item
        let title = displayTitle(item)
        return BillboardModel(
            id: item.id,
            title: title,
            // The store carries no synopsis yet: an episode shows its own name, a movie nothing.
            overview: item.seriesName == nil ? "" : item.name,
            // The logo of an episode is its series' (`logoItemId`); without one the billboard shows the title as text.
            logo: imageURL(item.logoItemId ?? item.id, .logo, item.logoImageTag, logoImageWidth),
            backdrop: ArtworkSource(url: imageURL(item.id, .primary, item.primaryImageTag, billboardImageWidth), placeholderTitle: title),
            runtimeMinutes: item.runtimeTicks.map { Int($0 / 600_000_000) },
            isInList: isInList
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
            image: ArtworkSource(url: imageURL(item.id, .primary, item.primaryImageTag, landscapeImageWidth), placeholderTitle: title),
            progress: entry.userData.progress(runtimeTicks: item.runtimeTicks)
        )
    }

    static func poster(_ entry: LibraryEntry, imageURL: ImageURL) -> PosterModel {
        let item = entry.item
        let title = displayTitle(item)
        return PosterModel(
            id: item.id,
            detailId: item.kind == .episode ? item.seriesId : nil,
            title: title,
            subtitle: item.seriesName == nil ? nil : item.name,
            image: ArtworkSource(url: imageURL(item.id, .primary, item.primaryImageTag, posterImageWidth), placeholderTitle: title),
            isWatched: entry.userData.played
        )
    }

    static func remainingText(_ entry: LibraryEntry) -> String? {
        guard let runtime = entry.item.runtimeTicks, entry.userData.playbackPositionTicks > 0, !entry.userData.played else { return nil }
        return MediaFormat.remaining(seconds: Double(runtime - entry.userData.playbackPositionTicks) / ticksPerSecond)
    }
}
