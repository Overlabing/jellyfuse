import Foundation

/// Watch progress clamped to `0...1`; nil when there is nothing to show.
func normalizedProgress(_ value: Double?) -> Double? {
    guard let value, value > 0 else { return nil }
    return min(value, 1)
}

/// Display value of a poster (2:3) card.
public struct PosterModel: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let image: ArtworkSource
    public let progress: Double?
    public let isWatched: Bool

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        image: ArtworkSource,
        progress: Double? = nil,
        isWatched: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.image = image
        self.progress = normalizedProgress(progress)
        self.isWatched = isWatched
    }

    /// VoiceOver label: `Nocturne, 2025, repris à 62 %`.
    public var accessibilityDescription: String {
        let watched = isWatched ? String(localized: "vu") : nil
        return [title, subtitle, MediaFormat.resumeDescription(progress: progress), watched]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

/// Display value of a landscape (16:9) card: continue watching, next up, episodes.
public struct LandscapeModel: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let image: ArtworkSource
    public let progress: Double?
    public let isWatched: Bool

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        image: ArtworkSource,
        progress: Double? = nil,
        isWatched: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.image = image
        self.progress = normalizedProgress(progress)
        self.isWatched = isWatched
    }

    public var accessibilityDescription: String {
        let watched = isWatched ? String(localized: "vu") : nil
        return [title, subtitle, MediaFormat.resumeDescription(progress: progress), watched]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

/// Display value of the home billboard.
public struct BillboardModel: Sendable, Equatable, Identifiable {
    public enum MetaPart: Sendable, Equatable {
        case rating(String)
        case text(String)
    }

    public let id: String
    public let title: String
    public let overview: String
    public let backdrop: ArtworkSource
    public let rating: Double?
    public let year: Int?
    public let runtimeMinutes: Int?

    public init(
        id: String,
        title: String,
        overview: String,
        backdrop: ArtworkSource,
        rating: Double? = nil,
        year: Int? = nil,
        runtimeMinutes: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.overview = overview
        self.backdrop = backdrop
        self.rating = rating
        self.year = year
        self.runtimeMinutes = runtimeMinutes
    }

    /// The single meta line: `★ 7,8 · 2025 · 2 h 08`. Missing values are skipped.
    public func metaParts(locale: Locale = .current) -> [MetaPart] {
        var parts: [MetaPart] = []
        if let rating, let text = MediaFormat.rating(rating, locale: locale) {
            parts.append(.rating("★ \(text)"))
        }
        if let year { parts.append(.text(String(year))) }
        if let runtimeMinutes, let text = MediaFormat.runtime(minutes: runtimeMinutes) {
            parts.append(.text(text))
        }
        return parts
    }
}

/// Display value of the detail header (movie or series).
public struct DetailHeaderModel: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    /// The title as an image (Jellyfin `Logo`); nil shows the title as text.
    public let logo: URL?
    public let backdrop: ArtworkSource
    public let overview: String
    public let rating: Double?
    /// Age rating (`TP`, `PG-13`).
    public let certification: String?
    /// `2025` or `2022 – 2025`.
    public let yearText: String?
    public let runtimeMinutes: Int?
    public let seasonCount: Int?
    public let genres: [String]

    public init(
        id: String,
        title: String,
        logo: URL? = nil,
        backdrop: ArtworkSource,
        overview: String = "",
        rating: Double? = nil,
        certification: String? = nil,
        yearText: String? = nil,
        runtimeMinutes: Int? = nil,
        seasonCount: Int? = nil,
        genres: [String] = []
    ) {
        self.id = id
        self.title = title
        self.logo = logo
        self.backdrop = backdrop
        self.overview = overview
        self.rating = rating
        self.certification = certification
        self.yearText = yearText
        self.runtimeMinutes = runtimeMinutes
        self.seasonCount = seasonCount
        self.genres = genres
    }

    /// Genres shown on the meta line.
    public static let genreLimit = 3

    /// The single meta line: `★ 7,8 · TP · 2025 · 2 h 08 · Drame, Thriller`. Missing values are skipped.
    public func metaParts(locale: Locale = .current) -> [BillboardModel.MetaPart] {
        var parts: [BillboardModel.MetaPart] = []
        if let rating, let text = MediaFormat.rating(rating, locale: locale) { parts.append(.rating("★ \(text)")) }
        if let certification, !certification.isEmpty { parts.append(.text(certification)) }
        if let yearText { parts.append(.text(yearText)) }
        if let seasonCount, seasonCount > 0 {
            parts.append(.text(String(localized: "\(seasonCount) saisons")))
        } else if let runtimeMinutes, let text = MediaFormat.runtime(minutes: runtimeMinutes) {
            parts.append(.text(text))
        }
        if !genres.isEmpty { parts.append(.text(genres.prefix(Self.genreLimit).joined(separator: ", "))) }
        return parts
    }
}
