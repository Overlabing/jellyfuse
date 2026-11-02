import Foundation
import LibraryKit

/// The next episode of a series and how the end-of-episode card names it.
public enum UpNext {
    /// `S1E5 · Titre`.
    public static func title(of item: MediaItem) -> String {
        let code: String? = switch (item.parentIndexNumber, item.indexNumber) {
        case let (season?, episode?): "S\(season)E\(episode)"
        case let (nil, episode?): "E\(episode)"
        default: nil
        }
        return [code, item.name].compactMap { $0 }.joined(separator: " · ")
    }

    /// The episode after `id` in the series' order (season then episode), nil for the last one or an unknown id.
    public static func next(after id: String, in episodes: [LibraryEntry]) -> MediaItem? {
        guard let index = episodes.firstIndex(where: { $0.item.id == id }), index + 1 < episodes.count else { return nil }
        return episodes[index + 1].item
    }
}
