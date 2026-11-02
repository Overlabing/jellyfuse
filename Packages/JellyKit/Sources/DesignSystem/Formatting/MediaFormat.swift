import Foundation

/// Pure display formatting for durations and metadata lines (French source strings, `.xcstrings` later).
public enum MediaFormat {
    /// `2 h 08`, `1 h 00`, `45 min`. Nil for non-positive durations.
    public static func runtime(minutes: Int) -> String? {
        guard minutes > 0 else { return nil }
        guard minutes >= 60 else { return "\(minutes) min" }
        let (hours, rest) = minutes.quotientAndRemainder(dividingBy: 60)
        return "\(hours) h \(rest < 10 ? "0" : "")\(rest)"
    }

    /// `28 min restantes`, `1 h 12 restantes`. Rounds up to the next minute; nil when nothing remains.
    public static func remaining(seconds: TimeInterval) -> String? {
        guard seconds > 0 else { return nil }
        let minutes = Int((seconds / 60).rounded(.up))
        guard let runtime = runtime(minutes: minutes) else { return nil }
        return String(localized: "\(runtime) restantes", bundle: .module)
    }

    /// A playback position as `0 h 12`, `1 h 05` (minutes rounded down). Nil for non-positive positions.
    public static func position(seconds: TimeInterval) -> String? {
        guard seconds > 0 else { return nil }
        let (hours, minutes) = (Int(seconds) / 60).quotientAndRemainder(dividingBy: 60)
        return "\(hours) h \(minutes < 10 ? "0" : "")\(minutes)"
    }

    /// `7,8` for fr, `7.8` for en. Nil when the rating is not positive.
    public static func rating(_ value: Double, locale: Locale = .current) -> String? {
        guard value > 0 else { return nil }
        return String(format: "%.1f", locale: locale, value)
    }

    /// Accessibility summary of watch progress: `repris à 62 %` (or nil).
    public static func resumeDescription(progress: Double?) -> String? {
        guard let progress, progress > 0 else { return nil }
        let percent = Int((progress * 100).rounded())
        return String(localized: "repris à \(percent) %", bundle: .module)
    }
}
