import Foundation

/// When the on-screen display is shown. It appears on any interaction, disappears `inactivityDelay` after
/// the last one while the video plays, and stays while it is paused or scrubbed. Pure: the screen owns the
/// timer and calls `expire` at `deadline`.
public struct OSDVisibility: Sendable, Equatable {
    public static let inactivityDelay: TimeInterval = 4

    public private(set) var isVisible = false
    /// When to hide; nil while the display must stay.
    public private(set) var deadline: Date?

    public init() {}

    /// Shows the display; while playing it arms the inactivity timer, otherwise it stays.
    public mutating func reveal(isPlaying: Bool, now: Date) {
        isVisible = true
        deadline = isPlaying ? now.addingTimeInterval(Self.inactivityDelay) : nil
    }

    /// Shows the display until `hide()` (paused, scrubbing).
    public mutating func hold() {
        isVisible = true
        deadline = nil
    }

    public mutating func hide() {
        isVisible = false
        deadline = nil
    }

    /// Hides the display if the timer is due.
    public mutating func expire(now: Date) {
        guard let deadline, deadline <= now else { return }
        hide()
    }
}
