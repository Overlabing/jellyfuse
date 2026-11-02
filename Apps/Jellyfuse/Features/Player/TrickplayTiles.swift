import CoreGraphics
import Foundation
import ImageIO
import LibraryKit
import Observation
import SwiftUI

/// The scrub thumbnails of one playback: downloads the trickplay tile images on demand and cuts the frame for a
/// position out of them. A tile is a big decoded bitmap (a 10 × 10 grid of 320 px frames), so only the last few
/// are kept; scrubbing stays inside a couple of tiles.
@MainActor
@Observable
final class TrickplayTiles {
    private static let capacity = 3

    private var tiles: [Int: CGImage] = [:]
    /// Tile indexes, oldest first, for eviction.
    private var order: [Int] = []
    private var loading: Set<Int> = []
    private let urlForTile: (_ width: Int, _ index: Int) -> URL?

    /// `urlForTile` maps a tile of a given width to its (authenticated) URL: never log it.
    init(urlForTile: @escaping (_ width: Int, _ index: Int) -> URL?) {
        self.urlForTile = urlForTile
    }

    /// The frame for `seconds`, once its tile is in; nil while it is still loading.
    func thumbnail(for sheet: TrickplaySheet, at seconds: Double) -> Image? {
        let (index, rect) = sheet.tile(at: seconds)
        guard let frame = tiles[index]?.cropping(to: rect) else { return nil }
        return Image(decorative: frame, scale: 1)
    }

    /// Downloads and decodes the tile unless it is in or on its way. A failure leaves the bubble text-only.
    func load(tile index: Int, of sheet: TrickplaySheet) async {
        guard tiles[index] == nil, !loading.contains(index), let url = urlForTile(sheet.width, index) else { return }
        loading.insert(index)
        defer { loading.remove(index) }
        guard let image = await Self.fetch(url) else { return }
        tiles[index] = image
        order.append(index)
        if order.count > Self.capacity { tiles[order.removeFirst()] = nil }
    }

    private nonisolated static func fetch(_ url: URL) async -> CGImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}
