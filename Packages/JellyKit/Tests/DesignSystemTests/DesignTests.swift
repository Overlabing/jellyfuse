import Foundation
import Testing
@testable import DesignSystem

@Suite struct DesignTokenTests {
    @Test func paletteMatchesMockups() {
        #expect(Design.Palette.canvasHex == 0x07070B)
        #expect(Design.Palette.accentHex == 0x8A6CFF)
        #expect(Design.Palette.sparkHex == 0xFF5C8A)
        #expect(Design.Palette.gradientMidHex == 0xC65BDB)
    }

    @Test func gridMatchesHIG() {
        #expect(Design.Metrics.tv.poster == CGSize(width: 260, height: 390))
        #expect(Design.Metrics.tv.landscape == CGSize(width: 410, height: 231))
        #expect(Design.Metrics.tv.screenMargin == 80)
        #expect(Design.Metrics.tv.shelfGap == 40)
        #expect(Design.Metrics.tv.gridRowGap >= 100)
    }

    @Test func posterIsTwoByThree() {
        #expect(abs(Design.Metrics.tv.poster.width / Design.Metrics.tv.poster.height - 2.0 / 3.0) < 1e-9)
    }

    @Test func scrimStopsAreParallel() {
        #expect(Design.Scrim.leftOpacities.count == Design.Scrim.leftLocations.count)
        #expect(Design.Scrim.bottomOpacities.count == Design.Scrim.bottomLocations.count)
        #expect(Design.Scrim.topOpacities.count == Design.Scrim.topLocations.count)
    }
}

@Suite struct MediaFormatTests {
    @Test(arguments: [(45, "45 min"), (60, "1 h 00"), (68, "1 h 08"), (128, "2 h 08"), (72, "1 h 12")])
    func runtime(minutes: Int, expected: String) {
        #expect(MediaFormat.runtime(minutes: minutes) == expected)
    }

    @Test func runtimeRejectsNonPositive() {
        #expect(MediaFormat.runtime(minutes: 0) == nil)
        #expect(MediaFormat.runtime(minutes: -5) == nil)
    }

    @Test func remainingRoundsUp() {
        #expect(MediaFormat.remaining(seconds: 28 * 60) == "28 min restantes")
        #expect(MediaFormat.remaining(seconds: 28 * 60 + 1) == "29 min restantes")
        #expect(MediaFormat.remaining(seconds: 72 * 60) == "1 h 12 restantes")
        #expect(MediaFormat.remaining(seconds: 0) == nil)
    }

    @Test func ratingUsesLocaleDecimalSeparator() {
        #expect(MediaFormat.rating(7.8, locale: Locale(identifier: "fr_FR")) == "7,8")
        #expect(MediaFormat.rating(7.8, locale: Locale(identifier: "en_US")) == "7.8")
        #expect(MediaFormat.rating(0) == nil)
    }

    @Test func resumeDescription() {
        #expect(MediaFormat.resumeDescription(progress: 0.62) == "repris à 62 %")
        #expect(MediaFormat.resumeDescription(progress: nil) == nil)
        #expect(MediaFormat.resumeDescription(progress: 0) == nil)
    }
}

@Suite struct ModelTests {
    private let art = ArtworkSource(url: nil, placeholderTitle: "N")

    @Test func progressIsClamped() {
        #expect(PosterModel(id: "1", title: "A", image: art, progress: 1.7).progress == 1)
        #expect(PosterModel(id: "1", title: "A", image: art, progress: -0.2).progress == nil)
        #expect(LandscapeModel(id: "1", title: "A", image: art, progress: 0.4).progress == 0.4)
    }

    @Test func posterAccessibilityDescription() {
        let model = PosterModel(id: "1", title: "Nocturne", subtitle: "2025", image: art, progress: 0.62)
        #expect(model.accessibilityDescription == "Nocturne, 2025, repris à 62 %")
        let watched = PosterModel(id: "2", title: "Atlas", image: art, isWatched: true)
        #expect(watched.accessibilityDescription == "Atlas, vu")
    }

    @Test func billboardMetaLine() {
        let model = BillboardModel(
            id: "b", title: "Nocturne", overview: "", backdrop: art,
            rating: 7.8, year: 2025, runtimeMinutes: 128
        )
        #expect(model.metaParts(locale: Locale(identifier: "fr_FR")) == [.rating("★ 7,8"), .text("2025"), .text("2 h 08")])
    }

    @Test func billboardMetaSkipsMissingValues() {
        let model = BillboardModel(id: "b", title: "T", overview: "", backdrop: art, year: 2025)
        #expect(model.metaParts() == [.text("2025")])
    }
}

@Suite struct PlaceholderStyleTests {
    @Test func hueIsStableAndInRange() {
        for title in ["Nocturne", "La Dernière Marée", "", "日本語"] {
            let hue = PlaceholderStyle.hue(for: title)
            #expect(hue == PlaceholderStyle.hue(for: title))
            #expect((0..<360).contains(hue))
        }
        #expect(PlaceholderStyle.hue(for: "Nocturne") != PlaceholderStyle.hue(for: "Atlas"))
    }

    @Test func initialSkipsPunctuation() {
        #expect(PlaceholderStyle.initial(for: "nocturne") == "N")
        #expect(PlaceholderStyle.initial(for: "  «Éclat»") == "É")
        #expect(PlaceholderStyle.initial(for: "") == "?")
    }

    @Test func hslConversion() {
        #expect(PlaceholderStyle.rgb(hue: 0, saturation: 1, lightness: 0.5) == .init(red: 1, green: 0, blue: 0))
        let blue = PlaceholderStyle.rgb(hue: 240, saturation: 1, lightness: 0.5)
        #expect(abs(blue.blue - 1) < 1e-9 && abs(blue.red) < 1e-9)
        let grey = PlaceholderStyle.rgb(hue: 123, saturation: 0, lightness: 0.4)
        #expect(abs(grey.red - 0.4) < 1e-9 && abs(grey.green - 0.4) < 1e-9)
    }
}
