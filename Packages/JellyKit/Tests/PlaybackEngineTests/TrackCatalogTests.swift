import Foundation
import JellyfinAPI
import Testing
@testable import PlaybackEngine

@Suite struct TrackCatalogTests {
    private let fr = Locale(identifier: "fr_FR")

    private func streams() -> [MediaStream] {
        var eac3 = stream(1, .audio, codec: "eac3", language: "fre", isDefault: true)
        eac3.channelLayout = "5.1(side)"
        var stereo = stream(2, .audio, codec: "aac", language: "eng")
        stereo.channels = 2
        var forced = stream(4, .subtitle, codec: "subrip", language: "fre", isForced: true)
        forced.isHearingImpaired = false
        var sdh = stream(5, .subtitle, codec: "hdmv_pgs_subtitle", language: "eng")
        sdh.isHearingImpaired = true
        return [stream(0, .video, codec: "hevc"), eac3, stereo, forced, sdh, stream(6, .subtitle, codec: "srt", language: "spa", isExternal: true)]
    }

    @Test func audioTracksAreNamedAndMapped() {
        let catalog = TrackCatalog(streams: streams(), externalIndices: [6], locale: fr)
        #expect(catalog.audio.map(\.title) == ["Français", "Anglais"])
        #expect(catalog.audio.map(\.detail) == ["EAC3 5.1", "AAC 2.0"])
        #expect(catalog.audio.map(\.mpvID) == [1, 2])
        #expect(catalog.audio.map(\.index) == [1, 2])
    }

    @Test func subtitleTracksCarryFlagsAndGroupAwareIDs() {
        let catalog = TrackCatalog(streams: streams(), externalIndices: [6], locale: fr)
        #expect(catalog.subtitles.map(\.title) == ["Français " + tr(fr: "(forcés)", en: "(forced)"), "Anglais SDH", "Espagnol"])
        #expect(catalog.subtitles.map(\.detail) == ["SRT", "PGS", "SRT"])
        // Embedded first (file order), then the sub-added sidecar.
        #expect(catalog.subtitles.map(\.mpvID) == [1, 2, 3])
        #expect(catalog.subtitles.map(\.isExternal) == [false, false, true])
    }

    @Test func aSidecarThatWasNotAddedIsNotListed() {
        let catalog = TrackCatalog(streams: streams(), externalIndices: [], locale: fr)
        #expect(catalog.subtitles.map(\.index) == [4, 5])
    }

    @Test func unknownLanguageFallsBackToAPositionalName() {
        let catalog = TrackCatalog(streams: [stream(3, .audio, codec: "ac3", language: "und")], externalIndices: [], locale: fr)
        #expect(catalog.audio.first?.title == tr(fr: "Piste 4", en: "Track 4"))
    }

    @Test func lookupByJellyfinIndex() {
        let catalog = TrackCatalog(streams: streams(), externalIndices: [6], locale: fr)
        #expect(catalog.audioTrack(at: 2)?.mpvID == 2)
        #expect(catalog.subtitleTrack(at: 6)?.mpvID == 3)
        #expect(catalog.subtitleTrack(at: nil) == nil)
    }
}

@Suite struct TrackPreferenceTests {
    private func defaults() -> UserDefaults {
        let suite = "trackpref-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func choicesBecomeLanguagePreferences() {
        #expect(TrackPref.audio(stream(1, .audio, language: "jpn")) == .language("jpn", isExternal: false))
        #expect(TrackPref.audio(stream(1, .audio)) == nil)
        #expect(TrackPref.subtitle(stream(4, .subtitle, language: "fre", isExternal: true)) == .language("fre", isExternal: true))
        #expect(TrackPref.subtitle(nil) == .off)
    }

    @Test func rememberedPerScopeAndOwner() {
        let defaults = defaults()
        let store = TrackPreferenceStore(owner: "srv|u1", defaults: defaults)
        store.rememberAudio(.language("jpn", isExternal: false), scope: "series1")
        store.rememberSubtitle(.off, scope: "series1")
        #expect(store.audio(scope: "series1") == .language("jpn", isExternal: false))
        #expect(store.subtitle(scope: "series1") == .off)
        #expect(store.audio(scope: "series2") == nil)
        #expect(TrackPreferenceStore(owner: "srv|u2", defaults: defaults).audio(scope: "series1") == nil)
    }

    @Test func aChoiceWithNothingToRememberKeepsTheOldOne() {
        let store = TrackPreferenceStore(owner: "o", defaults: defaults())
        store.rememberAudio(.language("fre", isExternal: false), scope: "m")
        store.rememberAudio(nil, scope: "m")
        #expect(store.audio(scope: "m") == .language("fre", isExternal: false))
    }

    @Test func removeAllForgetsOnlyThisOwnersChoices() {
        let defaults = defaults()
        let mine = TrackPreferenceStore(owner: "srv|u1", defaults: defaults)
        let other = TrackPreferenceStore(owner: "srv|u2", defaults: defaults)
        mine.rememberAudio(.language("jpn", isExternal: false), scope: "a")
        mine.rememberSubtitle(.off, scope: "b")
        other.rememberAudio(.language("fre", isExternal: false), scope: "a")
        mine.removeAll()
        #expect(mine.audio(scope: "a") == nil)
        #expect(mine.subtitle(scope: "b") == nil)
        #expect(other.audio(scope: "a") == .language("fre", isExternal: false))
    }

    @Test func scopeIsTheSeriesForAnEpisode() {
        #expect(TrackPreferenceStore.scope(itemId: "ep1", seriesId: "s1") == "s1")
        #expect(TrackPreferenceStore.scope(itemId: "m1", seriesId: nil) == "m1")
    }

    @Test func rememberedChoiceFeedsTheNextResolution() {
        let store = TrackPreferenceStore(owner: "o", defaults: defaults())
        store.rememberAudio(.language("eng", isExternal: false), scope: "s1")
        store.rememberSubtitle(.language("fre", isExternal: false), scope: "s1")
        let src = source(streams: [
            stream(1, .audio, language: "fre", isDefault: true), stream(2, .audio, language: "eng"),
            stream(3, .subtitle, language: "eng"), stream(4, .subtitle, language: "fre"),
        ])
        let selection = TrackSelection.choose(from: src, input: store.input(scope: "s1"))
        #expect(selection.audioIndex == 2)
        #expect(selection.subtitleIndex == 4)
    }
}
