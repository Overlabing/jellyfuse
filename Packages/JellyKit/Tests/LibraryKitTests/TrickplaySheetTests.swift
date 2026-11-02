import CoreGraphics
import Foundation
import JellyfinAPI
import Testing
@testable import LibraryKit

@Suite struct TrickplaySheetTests {
    /// 320 × 180 frames every 10 s, 10 × 10 per tile, 250 frames (two and a half tiles).
    private let sheet = TrickplaySheet(
        width: 320, thumbnailWidth: 320, thumbnailHeight: 180, columns: 10, rows: 10, intervalMilliseconds: 10_000, thumbnailCount: 250
    )!

    @Test func startIsTheFirstFrameOfTheFirstTile() {
        let (tile, rect) = sheet.tile(at: 0)
        #expect(tile == 0)
        #expect(rect == CGRect(x: 0, y: 0, width: 320, height: 180))
    }

    @Test func framesFillARowThenTheNextRow() {
        // 35 s -> frame 3 (column 3, row 0); 120 s -> frame 12 (column 2, row 1).
        #expect(sheet.tile(at: 35).cropRect == CGRect(x: 960, y: 0, width: 320, height: 180))
        #expect(sheet.tile(at: 120).cropRect == CGRect(x: 640, y: 180, width: 320, height: 180))
    }

    @Test func aFullTileRollsOverToTheNextOne() {
        // Frame 100 is the first of tile 1; frame 99 the last of tile 0.
        #expect(sheet.tile(at: 1000).tileIndex == 1)
        #expect(sheet.tile(at: 1000).cropRect.origin == .zero)
        let last = sheet.tile(at: 999.9)
        #expect(last.tileIndex == 0)
        #expect(last.cropRect.origin == CGPoint(x: 2880, y: 1620))
    }

    @Test func positionsOutOfRangeClampToTheFirstAndLastFrames() {
        #expect(sheet.tile(at: -5) == sheet.tile(at: 0))
        #expect(sheet.tile(at: .nan) == sheet.tile(at: 0))
        let end = sheet.tile(at: 100_000)
        // Frame 249: tile 2, slot 49 -> column 9, row 4.
        #expect(end.tileIndex == 2)
        #expect(end.cropRect == CGRect(x: 2880, y: 720, width: 320, height: 180))
    }

    @Test func aGridThatCannotExistIsRejected() {
        #expect(TrickplaySheet(width: 320, thumbnailWidth: 320, thumbnailHeight: 180, columns: 0, rows: 10, intervalMilliseconds: 10_000, thumbnailCount: 5) == nil)
        #expect(TrickplaySheet(width: 320, thumbnailWidth: 320, thumbnailHeight: 180, columns: 10, rows: 10, intervalMilliseconds: 0, thumbnailCount: 5) == nil)
    }

    // MARK: Manifest

    private func info(width: Int) -> TrickplayInfoDto {
        TrickplayInfoDto(height: width * 9 / 16, interval: 10_000, thumbnailCount: 100, tileHeight: 10, tileWidth: 10, width: width)
    }

    @Test func theWidthClosestTo320IsChosen() {
        let manifest = ["src": ["160": info(width: 160), "480": info(width: 480), "640": info(width: 640)]]
        #expect(TrickplaySheet.preferred(from: manifest, mediaSourceId: "src")?.width == 480)
    }

    @Test func theItemsOwnSourceWinsAndAnotherStandsInWhenUnlisted() {
        let manifest = ["a": ["320": info(width: 320)], "b": ["160": info(width: 160)]]
        #expect(TrickplaySheet.preferred(from: manifest, mediaSourceId: "b")?.width == 160)
        #expect(TrickplaySheet.preferred(from: manifest, mediaSourceId: "zzz")?.width == 320)
    }

    @Test func noManifestMeansNoTrickplay() {
        #expect(TrickplaySheet.preferred(from: nil, mediaSourceId: "a") == nil)
        #expect(TrickplaySheet.preferred(from: [:], mediaSourceId: "a") == nil)
        #expect(TrickplaySheet.preferred(from: ["a": ["x": info(width: 320)]], mediaSourceId: "a") == nil)
    }

    /// A playback started without the detail screen reads the manifest of `/Items/{id}` with the resolved source id.
    @Test func theResolvedMediaSourceIdSelectsTheManifestEntryOfAnItemDecodedFromTheServer() throws {
        let json = """
        {"Id": "item1", "Trickplay": {
            "item1": {"320": {"Width": 320, "Height": 180, "TileWidth": 10, "TileHeight": 10, "Interval": 10000, "ThumbnailCount": 100}},
            "other": {"160": {"Width": 160, "Height": 90, "TileWidth": 10, "TileHeight": 10, "Interval": 10000, "ThumbnailCount": 100}}
        }}
        """
        let dto = try JSONDecoder().decode(BaseItemDto.self, from: Data(json.utf8))
        #expect(TrickplaySheet.preferred(from: dto.trickplay, mediaSourceId: "item1")?.width == 320)
        #expect(TrickplaySheet.preferred(from: dto.trickplay, mediaSourceId: "other")?.width == 160)
    }
}
