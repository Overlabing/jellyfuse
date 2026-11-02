import Foundation
import JellyfinAPI

/// mpv's own numbering of the tracks, derived from Jellyfin stream indexes.
///
/// Subtitles are group-aware: mpv lists the container's subtitle tracks first, in file order, then
/// every `sub-add`ed file in the order it was added, whatever the order Jellyfin lists them in.
/// External subtitles are never in the static stream, so they are always `sub-add`ed (see
/// `ExternalSubtitle`) and sit after the embedded ones. Audio is always embedded: `aid` is the
/// 1-based position among the audio streams.
public enum MpvTrackMapping {
    /// `aid` for a Jellyfin audio stream index, nil if it is not an audio stream of `streams`.
    public static func audioID(forIndex index: Int?, streams: [MediaStream]) -> Int? {
        guard let index else { return nil }
        let audio = streams.filter { $0.type == .audio }.sorted { ($0.index ?? 0) < ($1.index ?? 0) }
        return audio.firstIndex(where: { $0.index == index }).map { $0 + 1 }
    }

    /// `sid` for a Jellyfin subtitle stream index. `addedExternalIndices` are the stream indexes of the
    /// sidecar files, in the order they are `sub-add`ed. Nil if the track is not selectable
    /// (the caller then sets `sid=no` explicitly: mpv would otherwise re-enable a default track).
    public static func subtitleID(forIndex index: Int?, streams: [MediaStream], addedExternalIndices: [Int]) -> Int? {
        guard let index else { return nil }
        let embedded = streams
            .filter { $0.type == .subtitle && $0.isExternal != true }
            .sorted { ($0.index ?? 0) < ($1.index ?? 0) }
        if let position = embedded.firstIndex(where: { $0.index == index }) { return position + 1 }
        if let position = addedExternalIndices.firstIndex(of: index) { return embedded.count + position + 1 }
        return nil
    }
}
