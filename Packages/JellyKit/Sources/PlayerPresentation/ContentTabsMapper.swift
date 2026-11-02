import DesignSystem
import Foundation
import LibraryKit
import PlaybackEngine

/// Builds the content panel's model from what is playing. Pure: the screen calls it with the current values.
public enum ContentTabsMapper {
    public struct Input {
        public var heading: String
        public var detail: ItemDetail?
        public var catalog: TrackCatalog
        /// Jellyfin stream indexes of the tracks playing; nil subtitle = off.
        public var audioIndex: Int?
        public var subtitleIndex: Int?
        public var chapters: [Chapter]
        public var position: Double
        public var canSwitchTracks: Bool

        public init(
            heading: String, detail: ItemDetail?, catalog: TrackCatalog, audioIndex: Int?, subtitleIndex: Int?,
            chapters: [Chapter], position: Double, canSwitchTracks: Bool
        ) {
            self.heading = heading
            self.detail = detail
            self.catalog = catalog
            self.audioIndex = audioIndex
            self.subtitleIndex = subtitleIndex
            self.chapters = chapters
            self.position = position
            self.canSwitchTracks = canSwitchTracks
        }
    }

    public static func model(_ input: Input) -> ContentTabsModel {
        ContentTabsModel(
            info: info(heading: input.heading, detail: input.detail),
            audio: input.catalog.audio.map { row($0, selected: $0.index == input.audioIndex) },
            subtitles: input.catalog.subtitles.map { row($0, selected: $0.index == input.subtitleIndex) },
            chapters: ChapterRow.rows(names: input.chapters.map(\.name), starts: input.chapters.map(\.startSeconds), position: input.position),
            canSwitchTracks: input.canSwitchTracks
        )
    }

    static func row(_ track: TrackOption, selected: Bool) -> TrackRow {
        TrackRow(id: track.index, title: track.title, detail: track.detail, isSelected: selected)
    }

    /// `2021 · 1 h 52 · PG-13 · Science-fiction, Drame`.
    static func info(heading: String, detail: ItemDetail?) -> InfoContent {
        guard let detail else { return InfoContent(title: heading) }
        let runtime = detail.item.runtimeTicks.flatMap { MediaFormat.runtime(minutes: Int($0 / 600_000_000)) }
        let facts = [
            detail.productionYear.map(String.init), runtime, detail.officialRating,
            detail.genres.isEmpty ? nil : detail.genres.prefix(3).joined(separator: ", "),
        ].compactMap { $0 }.joined(separator: " · ")
        return InfoContent(title: heading, facts: facts, synopsis: detail.overview ?? "")
    }
}
