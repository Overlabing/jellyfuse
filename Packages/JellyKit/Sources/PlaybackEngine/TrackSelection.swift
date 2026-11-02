import Foundation
import JellyfinAPI

/// The user's `SubtitleMode` (Jellyfin `SubtitlePlaybackMode`).
public enum SubtitleMode: String, Sendable, Equatable, Codable {
    case none, onlyForced, smart, `default`, always
}

/// Language and mode preferences from the user configuration.
public struct TrackPreferences: Sendable, Equatable {
    public var audioLanguage: String?
    public var subtitleLanguage: String?
    public var subtitleMode: SubtitleMode

    public init(audioLanguage: String? = nil, subtitleLanguage: String? = nil, subtitleMode: SubtitleMode = .default) {
        self.audioLanguage = audioLanguage
        self.subtitleLanguage = subtitleLanguage
        self.subtitleMode = subtitleMode
    }
}

/// A track choice the user made earlier, remembered per movie or series (data-plan §5.4).
/// The stream index is deliberately not kept: it differs between episodes, the language does not.
public enum TrackPref: Sendable, Equatable, Codable {
    /// Subtitles explicitly turned off. Meaningless for audio, which never turns off.
    case off
    case language(String, isExternal: Bool)
}

public struct TrackSelectionInput: Sendable, Equatable {
    public var preferences: TrackPreferences
    public var rememberedAudio: TrackPref?
    public var rememberedSubtitle: TrackPref?

    public init(preferences: TrackPreferences = .init(), rememberedAudio: TrackPref? = nil, rememberedSubtitle: TrackPref? = nil) {
        self.preferences = preferences
        self.rememberedAudio = rememberedAudio
        self.rememberedSubtitle = rememberedSubtitle
    }
}

/// Jellyfin stream indexes of the tracks to play. `subtitleIndex == nil` means subtitles off.
public struct TrackSelection: Sendable, Equatable {
    public var audioIndex: Int?
    public var subtitleIndex: Int?
    /// Whether the chosen subtitle is a sidecar file (to `sub-add`) or part of the container.
    public var subtitleDelivery: SubtitleDeliveryMethod?

    public init(audioIndex: Int? = nil, subtitleIndex: Int? = nil, subtitleDelivery: SubtitleDeliveryMethod? = nil) {
        self.audioIndex = audioIndex
        self.subtitleIndex = subtitleIndex
        self.subtitleDelivery = subtitleDelivery
    }

    /// The pure priority chain of data-plan §5.4 (RN `resolver.ts` and jellyfin-web `playbackmanager`).
    public static func choose(from source: MediaSourceInfo, input: TrackSelectionInput) -> TrackSelection {
        let streams = source.mediaStreams ?? []
        let audio = streams.filter { $0.type == .audio }
        let subtitles = streams.filter { $0.type == .subtitle }

        let chosenAudio = chooseAudio(audio, defaultIndex: source.defaultAudioStreamIndex, input: input)
        guard let subtitle = chooseSubtitle(
            subtitles, defaultIndex: source.defaultSubtitleStreamIndex, audio: chosenAudio, input: input
        ) else {
            return TrackSelection(audioIndex: chosenAudio?.index)
        }
        return TrackSelection(
            audioIndex: chosenAudio?.index, subtitleIndex: subtitle.index,
            subtitleDelivery: subtitle.isExternal == true ? .external : .embed
        )
    }

    // MARK: Audio

    private static func chooseAudio(_ audio: [MediaStream], defaultIndex: Int?, input: TrackSelectionInput) -> MediaStream? {
        // 1. Remembered language (an `off` entry means nothing for audio).
        if case .language(let language, _)? = input.rememberedAudio {
            let matches = audio.filter { sameLanguage($0.language, language) }
            if let pick = matches.first(where: { $0.isDefault == true }) ?? matches.first { return pick }
        }
        // 2. Server default, if the index still exists (a re-processed file makes it stale).
        if let defaultIndex, let pick = audio.first(where: { $0.index == defaultIndex }) { return pick }
        // 3. Preferred language, then the file's default, then the first track.
        if let language = input.preferences.audioLanguage {
            let matches = audio.filter { sameLanguage($0.language, language) }
            if let pick = matches.first(where: { $0.isDefault == true }) ?? matches.first { return pick }
        }
        return audio.first(where: { $0.isDefault == true }) ?? audio.first
    }

    // MARK: Subtitles

    /// `nil` = subtitles off.
    private static func chooseSubtitle(
        _ subtitles: [MediaStream], defaultIndex: Int?, audio: MediaStream?, input: TrackSelectionInput
    ) -> MediaStream? {
        // 1. Remembered choice. `off` ends the chain; a language with no track on this item falls through.
        switch input.rememberedSubtitle {
        case .off?:
            return nil
        case .language(let language, let isExternal)?:
            let matches = subtitles.filter { sameLanguage($0.language, language) }
            let pick = matches.first(where: { ($0.isExternal == true) == isExternal })
                ?? matches.first(where: { $0.isDefault == true }) ?? matches.first
            if let pick { return pick }
        case nil:
            break
        }
        // 2. Server default: -1 means off.
        if defaultIndex == -1 { return nil }
        if let defaultIndex, let pick = subtitles.first(where: { $0.index == defaultIndex }) { return pick }
        // 3. Mode.
        switch input.preferences.subtitleMode {
        case .none:
            return nil
        case .onlyForced:
            let forced = subtitles.filter { $0.isForced == true }
            return forced.first(where: { $0.isDefault == true }) ?? forced.first
        case .smart:
            guard let wanted = input.preferences.subtitleLanguage,
                  let audioLanguage = audio?.language, !sameLanguage(audioLanguage, wanted) else { return nil }
            return preferredLanguageTrack(subtitles, language: wanted)
        case .default, .always:
            return preferredLanguageTrack(subtitles, language: input.preferences.subtitleLanguage)
        }
    }

    private static func preferredLanguageTrack(_ subtitles: [MediaStream], language: String?) -> MediaStream? {
        if let language {
            let matches = subtitles.filter { sameLanguage($0.language, language) }
            if let pick = matches.first(where: { $0.isDefault == true }) ?? matches.first { return pick }
        }
        return subtitles.first(where: { $0.isDefault == true }) ?? subtitles.first
    }

    private static func sameLanguage(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return false }
        return a.caseInsensitiveCompare(b) == .orderedSame
    }
}
