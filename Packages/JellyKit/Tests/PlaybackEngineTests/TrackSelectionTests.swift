import JellyfinAPI
import Testing
@testable import PlaybackEngine

@Suite struct TrackSelectionTests {
    private let streams = [
        stream(0, .video, codec: "hevc"),
        stream(1, .audio, codec: "eac3", language: "eng", isDefault: true),
        stream(2, .audio, codec: "aac", language: "fra"),
        stream(3, .subtitle, codec: "subrip", language: "eng"),
        stream(4, .subtitle, codec: "pgssub", language: "fra", isDefault: true),
        stream(5, .subtitle, codec: "subrip", language: "fra", isForced: true),
        stream(6, .subtitle, codec: "srt", language: "fra", isExternal: true),
    ]

    private func choose(
        defaultAudio: Int? = nil, defaultSubtitle: Int? = nil, input: TrackSelectionInput = .init()
    ) -> TrackSelection {
        TrackSelection.choose(from: source(streams: streams, defaultAudio: defaultAudio, defaultSubtitle: defaultSubtitle), input: input)
    }

    // MARK: Audio

    @Test func audioRememberedLanguageBeatsServerDefault() {
        let selection = choose(defaultAudio: 1, input: .init(rememberedAudio: .language("FRA", isExternal: false)))
        #expect(selection.audioIndex == 2)
    }

    @Test func audioRememberedOffIsIgnored() {
        #expect(choose(defaultAudio: 2, input: .init(rememberedAudio: .off)).audioIndex == 2)
    }

    @Test func audioServerDefaultIsUsedOnlyWhileTheIndexExists() {
        #expect(choose(defaultAudio: 2).audioIndex == 2)
        #expect(choose(defaultAudio: 99).audioIndex == 1)
    }

    @Test func audioPreferredLanguageThenFileDefaultThenFirst() {
        #expect(choose(input: .init(preferences: .init(audioLanguage: "fra"))).audioIndex == 2)
        #expect(choose(input: .init(preferences: .init(audioLanguage: "deu"))).audioIndex == 1)
        let noDefault = TrackSelection.choose(
            from: source(streams: [stream(1, .audio, language: "eng"), stream(2, .audio, language: "fra")]), input: .init()
        )
        #expect(noDefault.audioIndex == 1)
    }

    // MARK: Subtitles

    @Test func subtitleRememberedOffStopsTheChain() {
        let selection = choose(defaultSubtitle: 3, input: .init(preferences: .init(subtitleMode: .always), rememberedSubtitle: .off))
        #expect(selection.subtitleIndex == nil)
    }

    @Test func subtitleRememberedLanguagePrefersTheSameKind() {
        let external = choose(input: .init(rememberedSubtitle: .language("fra", isExternal: true)))
        #expect(external.subtitleIndex == 6 && external.subtitleDelivery == .external)
        let embedded = choose(input: .init(rememberedSubtitle: .language("fra", isExternal: false)))
        #expect(embedded.subtitleIndex == 4 && embedded.subtitleDelivery == .embed)
    }

    @Test func subtitleRememberedLanguageAbsentFallsThrough() {
        let selection = choose(defaultSubtitle: 3, input: .init(rememberedSubtitle: .language("deu", isExternal: false)))
        #expect(selection.subtitleIndex == 3)
    }

    @Test func subtitleServerDefaultMinusOneMeansOffAndBeatsTheMode() {
        let selection = choose(defaultSubtitle: -1, input: .init(preferences: .init(subtitleMode: .always)))
        #expect(selection.subtitleIndex == nil)
    }

    @Test func subtitleModes() {
        #expect(choose(input: .init(preferences: .init(subtitleLanguage: "fra", subtitleMode: .none))).subtitleIndex == nil)
        // onlyForced: the forced track, nothing otherwise.
        #expect(choose(input: .init(preferences: .init(subtitleMode: .onlyForced))).subtitleIndex == 5)
        let unforced = TrackSelection.choose(
            from: source(streams: [stream(1, .audio, language: "eng"), stream(2, .subtitle, language: "eng")]),
            input: .init(preferences: .init(subtitleMode: .onlyForced))
        )
        #expect(unforced.subtitleIndex == nil)
        // always/default: preferred language (file default first), else the file default, else the first.
        #expect(choose(input: .init(preferences: .init(subtitleLanguage: "fra", subtitleMode: .always))).subtitleIndex == 4)
        #expect(choose(input: .init(preferences: .init(subtitleLanguage: "deu", subtitleMode: .default))).subtitleIndex == 4)
    }

    @Test func smartModeOnlyForeignAudio() {
        // Audio defaults to English (file default): a French preference means subtitles.
        let foreign = choose(input: .init(preferences: .init(subtitleLanguage: "fra", subtitleMode: .smart)))
        #expect(foreign.audioIndex == 1 && foreign.subtitleIndex == 4)
        // Audio in the preferred language: no subtitles.
        let native = choose(input: .init(preferences: .init(audioLanguage: "fra", subtitleLanguage: "fra", subtitleMode: .smart)))
        #expect(native.audioIndex == 2 && native.subtitleIndex == nil)
    }
}
