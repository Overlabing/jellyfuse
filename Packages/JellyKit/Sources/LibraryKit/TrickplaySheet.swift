import CoreGraphics
import Foundation
import JellyfinAPI

/// One width of an item's trickplay (scrub thumbnails): the server cuts the film into thumbnails every
/// `interval` and packs them `columns × rows` per tile image (`/Videos/{id}/Trickplay/{width}/{index}.jpg`).
public struct TrickplaySheet: Sendable, Equatable {
    /// The width the server calls this set; part of the tile URL.
    public let width: Int
    public let thumbnailWidth: Int
    public let thumbnailHeight: Int
    public let columns: Int
    public let rows: Int
    public let intervalSeconds: Double
    public let thumbnailCount: Int

    /// The width the bubble wants: sharp enough for a 320 pt bubble, small enough to download at once.
    public static let preferredWidth = 320

    /// Nil when the server's numbers cannot describe a grid.
    public init?(width: Int, thumbnailWidth: Int, thumbnailHeight: Int, columns: Int, rows: Int, intervalMilliseconds: Int, thumbnailCount: Int) {
        guard [width, thumbnailWidth, thumbnailHeight, columns, rows, intervalMilliseconds, thumbnailCount].allSatisfy({ $0 > 0 }) else { return nil }
        self.width = width
        self.thumbnailWidth = thumbnailWidth
        self.thumbnailHeight = thumbnailHeight
        self.columns = columns
        self.rows = rows
        intervalSeconds = Double(intervalMilliseconds) / 1000
        self.thumbnailCount = thumbnailCount
    }

    private var thumbnailsPerTile: Int { columns * rows }

    /// The tile image holding the thumbnail for `seconds`, and where that thumbnail sits in it (pixels).
    /// Positions before the start or past the end use the first or last thumbnail.
    public func tile(at seconds: Double) -> (tileIndex: Int, cropRect: CGRect) {
        let clamped = seconds.isFinite ? max(seconds, 0) : 0
        let thumbnail = min(Int(clamped / intervalSeconds), thumbnailCount - 1)
        let (tileIndex, slot) = thumbnail.quotientAndRemainder(dividingBy: thumbnailsPerTile)
        let (row, column) = slot.quotientAndRemainder(dividingBy: columns)
        let rect = CGRect(
            x: column * thumbnailWidth, y: row * thumbnailHeight, width: thumbnailWidth, height: thumbnailHeight
        )
        return (tileIndex, rect)
    }

    /// The set of the item's media source whose width is closest to `preferredWidth` (the manifest is
    /// `[mediaSourceId: [width: info]]`; the first source stands in when the id is not listed).
    public static func preferred(from manifest: [String: [String: TrickplayInfoDto]]?, mediaSourceId: String?) -> TrickplaySheet? {
        guard let manifest, let widths = mediaSourceId.flatMap({ manifest[$0] }) ?? manifest.sorted(by: { $0.key < $1.key }).first?.value else {
            return nil
        }
        return widths
            .compactMap { key, info in sheet(width: Int(key), info: info) }
            .min { abs($0.width - preferredWidth) < abs($1.width - preferredWidth) }
    }

    private static func sheet(width: Int?, info: TrickplayInfoDto) -> TrickplaySheet? {
        guard let width, let thumbnailWidth = info.width, let thumbnailHeight = info.height, let columns = info.tileWidth,
              let rows = info.tileHeight, let interval = info.interval, let count = info.thumbnailCount else { return nil }
        return TrickplaySheet(
            width: width, thumbnailWidth: thumbnailWidth, thumbnailHeight: thumbnailHeight, columns: columns, rows: rows,
            intervalMilliseconds: interval, thumbnailCount: count
        )
    }
}
