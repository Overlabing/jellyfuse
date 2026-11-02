import Foundation
import JellyfinAPI

/// One selectable track, with the two ids it lives under: Jellyfin's stream index (reports, memory) and
/// mpv's own id (`setTrack`). Already named for the viewer.
public struct TrackOption: Sendable, Equatable, Identifiable {
    /// Jellyfin stream index.
    public let index: Int
    /// mpv `aid` / `sid`.
    public let mpvID: Int
    /// `Français`, `Français (forcés)`, `English SDH`.
    public let title: String
    /// `EAC3 5.1`, `SRT`.
    public let detail: String
    public let language: String?
    public let isExternal: Bool

    public var id: Int { index }
}

/// The audio and subtitle tracks of the playing source that can be switched to without a restart.
///
/// Only tracks mpv can address are listed: an image-based sidecar was never `sub-add`ed, so it has no `sid`.
/// Empty when transcoding (the server already burnt the choice into the stream it sends).
public struct TrackCatalog: Sendable, Equatable {
    public let audio: [TrackOption]
    public let subtitles: [TrackOption]

    public static let empty = TrackCatalog(audio: [], subtitles: [])

    init(audio: [TrackOption], subtitles: [TrackOption]) {
        self.audio = audio
        self.subtitles = subtitles
    }

    /// `externalIndices`: the sidecar subtitles `sub-add`ed, in order (`ResolvedPlayback.externalSubtitles`).
    public init(streams: [MediaStream], externalIndices: [Int], locale: Locale = .current) {
        let ordered = streams.sorted { ($0.index ?? 0) < ($1.index ?? 0) }
        audio = ordered.compactMap { stream in
            guard stream.type == .audio, let index = stream.index,
                  let id = MpvTrackMapping.audioID(forIndex: index, streams: streams) else { return nil }
            return TrackOption(
                index: index, mpvID: id, title: Self.title(of: stream, locale: locale),
                detail: Self.audioDetail(of: stream), language: stream.language, isExternal: false
            )
        }
        subtitles = ordered.compactMap { stream in
            guard stream.type == .subtitle, let index = stream.index,
                  let id = MpvTrackMapping.subtitleID(forIndex: index, streams: streams, addedExternalIndices: externalIndices)
            else { return nil }
            return TrackOption(
                index: index, mpvID: id, title: Self.title(of: stream, locale: locale),
                detail: Self.subtitleCodec(stream.codec), language: stream.language, isExternal: stream.isExternal == true
            )
        }
    }

    public func audioTrack(at index: Int?) -> TrackOption? { audio.first { $0.index == index } }
    public func subtitleTrack(at index: Int?) -> TrackOption? { subtitles.first { $0.index == index } }

    // MARK: Names

    static func title(of stream: MediaStream, locale: Locale) -> String {
        var name = languageName(stream.language, locale: locale)
            ?? stream.localizedLanguage ?? stream.title
            ?? String(localized: "Piste \((stream.index ?? 0) + 1)")
        if stream.isForced == true { name += " " + String(localized: "(forcés)") }
        if stream.isHearingImpaired == true { name += " SDH" }
        return name
    }

    /// `fre` / `fra` / `fr` -> `français`, capitalized. Nil for an unknown or missing code.
    static func languageName(_ code: String?, locale: Locale) -> String? {
        guard let code, !code.isEmpty, code.lowercased() != "und" else { return nil }
        let name = locale.localizedString(forLanguageCode: iso639_1[code.lowercased()] ?? code)
        guard let name, name.caseInsensitiveCompare(code) != .orderedSame else { return nil }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Jellyfin sends ISO 639-2 codes; Foundation wants the two-letter ones for the common languages.
    private static let iso639_1 = [
        "fre": "fr", "fra": "fr", "eng": "en", "spa": "es", "ger": "de", "deu": "de", "ita": "it", "por": "pt",
        "jpn": "ja", "kor": "ko", "chi": "zh", "zho": "zh", "rus": "ru", "dut": "nl", "nld": "nl", "swe": "sv",
        "nor": "no", "dan": "da", "fin": "fi", "pol": "pl", "tur": "tr", "ara": "ar", "heb": "he", "hin": "hi",
        "cze": "cs", "ces": "cs", "hun": "hu", "gre": "el", "ell": "el", "tha": "th", "ukr": "uk", "cat": "ca",
    ]

    static func audioDetail(of stream: MediaStream) -> String {
        [stream.codec?.uppercased(), channels(of: stream)].compactMap { $0 }.joined(separator: " ")
    }

    private static func channels(of stream: MediaStream) -> String? {
        if let layout = stream.channelLayout, !layout.isEmpty {
            return String(layout.prefix { $0 != "(" })
        }
        switch stream.channels {
        case 1?: return "1.0"
        case 2?: return "2.0"
        case 6?: return "5.1"
        case 8?: return "7.1"
        default: return nil
        }
    }

    static func subtitleCodec(_ codec: String?) -> String {
        switch codec?.lowercased() {
        case "subrip", "srt": "SRT"
        case "hdmv_pgs_subtitle", "pgssub": "PGS"
        case "dvd_subtitle", "dvdsub": "VOBSUB"
        case "dvb_subtitle": "DVB"
        case let other?: other.uppercased()
        case nil: ""
        }
    }
}

extension TrackPref {
    /// What to remember after the viewer picked this audio track; nil when it has no language to match on.
    public static func audio(_ stream: MediaStream?) -> TrackPref? {
        guard let language = stream?.language, !language.isEmpty else { return nil }
        return .language(language, isExternal: false)
    }

    /// What to remember after the viewer picked this subtitle track (`nil` stream = subtitles off).
    public static func subtitle(_ stream: MediaStream?) -> TrackPref? {
        guard let stream else { return .off }
        guard let language = stream.language, !language.isEmpty else { return nil }
        return .language(language, isExternal: stream.isExternal == true)
    }
}

/// The viewer's last audio and subtitle choices, remembered per movie or series and per user, so the next
/// episode starts in the same language. The stream index is not kept (it differs between episodes).
public struct TrackPreferenceStore {
    private let defaults: UserDefaults
    private let owner: String

    /// `owner` is `Session.libraryOwner`.
    public init(owner: String, defaults: UserDefaults = .standard) {
        self.owner = owner
        self.defaults = defaults
    }

    /// The movie, or the series an episode belongs to.
    public static func scope(itemId: String, seriesId: String?) -> String { seriesId ?? itemId }

    public func audio(scope: String) -> TrackPref? { read(scope, "audio") }
    public func subtitle(scope: String) -> TrackPref? { read(scope, "subtitle") }

    public func rememberAudio(_ pref: TrackPref?, scope: String) { write(pref, scope, "audio") }
    public func rememberSubtitle(_ pref: TrackPref?, scope: String) { write(pref, scope, "subtitle") }

    /// The remembered choices, as the resolver's input.
    public func input(scope: String, preferences: TrackPreferences = .init()) -> TrackSelectionInput {
        TrackSelectionInput(preferences: preferences, rememberedAudio: audio(scope: scope), rememberedSubtitle: subtitle(scope: scope))
    }

    private func key(_ scope: String, _ kind: String) -> String { "trackpref|\(owner)|\(scope)|\(kind)" }

    private func read(_ scope: String, _ kind: String) -> TrackPref? {
        defaults.data(forKey: key(scope, kind)).flatMap { try? JSONDecoder().decode(TrackPref.self, from: $0) }
    }

    private func write(_ pref: TrackPref?, _ scope: String, _ kind: String) {
        guard let pref, let data = try? JSONEncoder().encode(pref) else { return }
        defaults.set(data, forKey: key(scope, kind))
    }
}
