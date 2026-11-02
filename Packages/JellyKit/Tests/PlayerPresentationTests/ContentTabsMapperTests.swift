import Foundation
import DesignSystem
import JellyfinAPI
import LibraryKit
import PlaybackEngine
import Testing
@testable import PlayerPresentation

@Suite struct ContentTabsMapperTests {
    private func stream(_ index: Int, _ type: MediaStreamType, language: String) -> MediaStream {
        var s = MediaStream()
        s.index = index
        s.type = type
        s.language = language
        s.codec = type == .audio ? "aac" : "subrip"
        return s
    }

    private func input(subtitle: Int?, detail: ItemDetail? = nil) -> ContentTabsMapper.Input {
        let streams = [
            stream(1, .audio, language: "fre"), stream(2, .audio, language: "eng"),
            stream(3, .subtitle, language: "fre"), stream(4, .subtitle, language: "eng"),
        ]
        return .init(
            heading: "Film", detail: detail, catalog: TrackCatalog(streams: streams, externalIndices: [], locale: Locale(identifier: "fr_FR")),
            audioIndex: 2, subtitleIndex: subtitle, chapters: [Chapter(name: "A", startSeconds: 0), Chapter(name: "B", startSeconds: 500)],
            position: 600, canSwitchTracks: true
        )
    }

    @Test func activeTracksAreChecked() {
        let model = ContentTabsMapper.model(input(subtitle: 3))
        #expect(model.audio.map(\.isSelected) == [false, true])
        #expect(model.subtitles.map(\.isSelected) == [true, false])
        #expect(model.subtitles.map(\.title) == ["Français", "Anglais"])
    }

    @Test func noSubtitleChecksOff() {
        let model = ContentTabsMapper.model(input(subtitle: nil))
        #expect(model.subtitles.allSatisfy { !$0.isSelected })
        #expect(TrackRow.subtitleList(model.subtitles).first?.isSelected == true)
    }

    @Test func chaptersFollowThePlayhead() {
        let model = ContentTabsMapper.model(input(subtitle: nil))
        #expect(model.chapters.map(\.isCurrent) == [false, true])
    }

    @Test func infoFallsBackToTheHeadingThenShowsFacts() {
        #expect(ContentTabsMapper.model(input(subtitle: nil)).info == InfoContent(title: "Film"))
        let detail = ItemDetail(
            item: MediaItem(id: "m", name: "Film", runtimeTicks: 67_200_000_000), overview: "Un résumé.",
            productionYear: 2021, officialRating: "PG-13", genres: ["Drame", "Science-fiction"]
        )
        let info = ContentTabsMapper.model(input(subtitle: nil, detail: detail)).info
        #expect(info.facts == "2021 · 1 h 52 · PG-13 · Drame, Science-fiction")
        #expect(info.synopsis == "Un résumé.")
    }
}
