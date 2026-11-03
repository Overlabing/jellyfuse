import Foundation

/// Which way a skip goes.
public enum SkipDirection: Sendable, Equatable {
    case backward
    case forward

    public var sign: Double { self == .backward ? -1 : 1 }
}

/// Pure position arithmetic of the transport controls.
public enum TransportMath {
    /// Length of a left / right click of the remote pad.
    public static let skipSeconds: Double = 10

    /// The position a skip lands on, kept inside the file. An unknown duration (0) only bounds the start.
    public static func skipTarget(from position: Double, direction: SkipDirection, duration: Double) -> Double {
        clamp(position + direction.sign * skipSeconds, duration: duration)
    }

    public static func clamp(_ seconds: Double, duration: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        let upper = duration.isFinite && duration > 0 ? duration : .greatestFiniteMagnitude
        return min(max(seconds, 0), upper)
    }
}

/// A seek is asynchronous: mpv keeps reporting the old position for a moment. The tracker holds the
/// requested target until the player catches up (or `settleTimeout` passes), so repeated skips build on
/// each other, the bar does not jump back, and the progress report carries where the viewer is going.
public struct SeekTracker: Sendable, Equatable {
    /// The player counts as arrived within this many seconds of the target (a seek may land on a keyframe).
    public static let tolerance: Double = 3
    /// A seek that never lands stops overriding the player after this long.
    public static let settleTimeout: TimeInterval = 3

    private var pending: (target: Double, at: Date)?

    public init() {}

    public mutating func seek(to target: Double, at now: Date) {
        pending = (target, now)
    }

    /// The position to show and report: the pending target, or the player's own position once it has settled.
    public func position(playerPosition: Double, at now: Date) -> Double {
        guard let pending, isSettling(playerPosition: playerPosition, at: now) else { return playerPosition }
        return pending.target
    }

    /// True while a seek is in flight: the player has not landed near the target yet. The screen shows a
    /// loading hint during it, so an intentional jump visibly acknowledges the press.
    public func isSettling(playerPosition: Double, at now: Date) -> Bool {
        guard let pending, now.timeIntervalSince(pending.at) < Self.settleTimeout else { return false }
        return abs(playerPosition - pending.target) > Self.tolerance
    }

    public static func == (lhs: SeekTracker, rhs: SeekTracker) -> Bool {
        lhs.pending?.target == rhs.pending?.target && lhs.pending?.at == rhs.pending?.at
    }
}

/// A scrub in progress: the playhead preview moves with the finger, the player does not until it is committed.
public struct ScrubSession: Sendable, Equatable {
    public let origin: Double
    public private(set) var target: Double
    public let duration: Double
    private var anchor: Double

    public init(origin: Double, duration: Double) {
        self.origin = origin
        self.duration = duration
        target = TransportMath.clamp(origin, duration: duration)
        anchor = target
    }

    /// Seconds covered by a swipe across the whole pad: a tenth of the file, within one to ten minutes.
    public static func span(duration: Double) -> Double {
        min(max(duration / 10, 60), 600)
    }

    /// A new swipe starts from where the previous one left the preview.
    public mutating func beginPan() { anchor = target }

    /// `fraction` is the swipe's travel since `beginPan()`, in pad widths (negative goes back).
    public mutating func pan(fraction: Double) {
        target = TransportMath.clamp(anchor + fraction * Self.span(duration: duration), duration: duration)
    }

    /// Absolute scrub by touch: the finger sets the playhead, `fraction` is 0...1 of the file.
    public mutating func scrub(toFraction fraction: Double) {
        let fraction = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        target = TransportMath.clamp(fraction * duration, duration: duration)
        anchor = target
    }

    /// A left / right click while scrubbing.
    public mutating func nudge(_ direction: SkipDirection) {
        target = TransportMath.skipTarget(from: target, direction: direction, duration: duration)
        anchor = target
    }
}

/// Pure arithmetic of the touch layer.
public enum TouchMath {
    /// A double-tap skips by half of the screen: left goes back, right goes forward.
    public static func skipDirection(tapX x: Double, width: Double) -> SkipDirection {
        x < width / 2 ? .backward : .forward
    }
}
