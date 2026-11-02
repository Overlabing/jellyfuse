import Foundation

/// Which end-of-episode card is due. Port of the RN client's `end-of-episode-gate` (itself from the Rust app).
public enum EndOfEpisodePhase: Sendable, Equatable {
    case idle
    /// Inside the closing-credits segment, with a next episode: « Regarder le générique » / « Épisode suivant ».
    case credits
    /// No credits segment (or past it) and the file is about to end: just « Épisode suivant ».
    case nearEnd
}

public enum EndOfEpisodeGate {
    /// Shorter files never get the near-end card.
    public static let minDuration: Double = 600
    /// Closer to the end than this, a countdown would not finish.
    public static let minRemaining: Double = 20
    /// Seconds from the card appearing to the next episode starting by itself.
    public static let countdownSeconds = 10
    /// A backward seek longer than this re-arms the card.
    public static let rearmSeek: Double = 2

    /// `credits` is the Outro segment, if the server has one.
    public static func targetPhase(position: Double, duration: Double, credits: ClosedRange<Double>?, hasNext: Bool) -> EndOfEpisodePhase {
        guard duration > 0 else { return .idle }
        let span = credits.flatMap { $0.upperBound > $0.lowerBound ? $0 : nil }
        if let span, hasNext, position >= span.lowerBound, position < span.upperBound { return .credits }
        guard duration >= minDuration else { return .idle }
        // The credits path has priority: the near-end one waits until the segment is over.
        if let span, position < span.upperBound { return .idle }
        let remaining = duration - position
        let showAt: Double = duration >= 3000 ? 40 : duration >= 2400 ? 35 : 30
        return remaining <= showAt && remaining >= minRemaining ? .nearEnd : .idle
    }
}

/// The card's phase and the two dismiss latches (one per path, so dismissing one does not lock the other).
public struct EndOfEpisodeState: Sendable, Equatable {
    public private(set) var phase = EndOfEpisodePhase.idle
    public private(set) var creditsDismissed = false
    public private(set) var nearEndDismissed = false

    public init() {}

    /// Optimistic callers are fine: re-entry and latched paths are ignored here.
    public mutating func enter(_ target: EndOfEpisodePhase) {
        guard target != .idle, phase != target else { return }
        if target == .credits, creditsDismissed { return }
        if target == .nearEnd, nearEndDismissed { return }
        phase = target
    }

    /// The window was left or the countdown ran out: clears the phase without latching, so a seek back into the
    /// window shows the card again.
    public mutating func complete() {
        phase = .idle
    }

    /// « Regarder le générique »: locks the credits path out, from any phase.
    public mutating func watchCredits() {
        phase = .idle
        creditsDismissed = true
    }

    /// Menu on the card: latches the path that is showing.
    public mutating func dismiss() {
        guard phase != .idle else { return }
        if phase == .credits { creditsDismissed = true } else { nearEndDismissed = true }
        phase = .idle
    }

    /// A backward seek: every flag clears.
    public mutating func reset() {
        self = EndOfEpisodeState()
    }

    public var isDismissed: Bool { creditsDismissed || nearEndDismissed }
}
