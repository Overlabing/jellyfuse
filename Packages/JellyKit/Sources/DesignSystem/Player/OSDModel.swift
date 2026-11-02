import Foundation

/// What the on-screen display shows, already formatted. Pure: built from the playback position, so the
/// view does no arithmetic.
public struct OSDModel: Sendable, Equatable {
    public let title: String
    /// Playhead, 0...1 of the file (0 while the duration is unknown).
    public let progress: Double
    public let elapsed: String
    /// `-0:26:36`; nil while the duration is unknown.
    public let remaining: String?
    /// `Se termine à 22 h 47`; nil while the duration is unknown.
    public let endsAt: String?
    /// The time under the playhead while scrubbing; nil otherwise.
    public let preview: String?
    /// Chapter markers on the bar, 0...1 of the file (see `ChapterMarks.fractions`).
    public let chapterMarks: [Double]
    /// The chapter under the playhead; shown with the scrub preview.
    public let chapterTitle: String?

    /// `position` is where the playhead is: the scrub target while scrubbing, the playback position otherwise.
    public init(
        title: String, position: Double, duration: Double, isScrubbing: Bool = false, chapterMarks: [Double] = [], chapterTitle: String? = nil,
        now: Date = .now, calendar: Calendar = .current
    ) {
        let position = Self.sanitized(position)
        let hasDuration = duration.isFinite && duration > 0
        let remainingSeconds = hasDuration ? max(duration - position, 0) : nil
        self.title = title
        self.chapterMarks = chapterMarks
        self.chapterTitle = chapterTitle
        progress = hasDuration ? min(position / duration, 1) : 0
        elapsed = Self.clock(position)
        remaining = remainingSeconds.map { "-" + Self.clock($0, rounding: .up) }
        endsAt = remainingSeconds.map { Self.endTime(now: now, remaining: $0, calendar: calendar) }
        preview = isScrubbing ? Self.clock(position) : nil
    }

    /// Film: its title. Episode: `Série › S1E4 · Titre`.
    public static func heading(name: String, seriesName: String?, season: Int?, episode: Int?) -> String {
        guard let seriesName else { return name }
        let code: String? = switch (season, episode) {
        case let (season?, episode?): "S\(season)E\(episode)"
        case let (nil, episode?): "E\(episode)"
        default: nil
        }
        let episodeLine = [code, name].compactMap { $0 }.joined(separator: " · ")
        return "\(seriesName) › \(episodeLine)"
    }

    /// `0:19:24`, hours always shown (mockup).
    public static func clock(_ seconds: Double, rounding: FloatingPointRoundingRule = .down) -> String {
        let total = Int(sanitized(seconds).rounded(rounding))
        let (hours, rest) = total.quotientAndRemainder(dividingBy: 3600)
        let (minutes, secs) = rest.quotientAndRemainder(dividingBy: 60)
        return "\(hours):\(minutes < 10 ? "0" : "")\(minutes):\(secs < 10 ? "0" : "")\(secs)"
    }

    /// `Se termine à 22 h 47` / `Ends at 10:47 PM`: the wall-clock time the file ends if it plays on from now.
    /// French keeps the mockup's `22 h 47`; other languages use the locale's own short time style.
    public static func endTime(now: Date, remaining: Double, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let end = now.addingTimeInterval(remaining)
        let time: String
        if locale.language.languageCode?.identifier == "fr" {
            let parts = calendar.dateComponents([.hour, .minute], from: end)
            let minute = parts.minute ?? 0
            time = "\(parts.hour ?? 0) h \(minute < 10 ? "0" : "")\(minute)"
        } else {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = locale
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            time = formatter.string(from: end)
        }
        return String(localized: "Se termine à \(time)", bundle: .module)
    }

    private static func sanitized(_ seconds: Double) -> Double {
        seconds.isFinite ? max(seconds, 0) : 0
    }
}
