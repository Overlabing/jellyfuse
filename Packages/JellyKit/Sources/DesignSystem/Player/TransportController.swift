import Foundation
import Observation

/// What the display shows besides its values.
public struct OSDState: Sendable, Equatable {
    public var isVisible: Bool
    public var isPaused: Bool
    public var isScrubbing: Bool
    /// The last ±10 s skip, until it is cleared.
    public var skip: SkipFeedback?

    public init(isVisible: Bool = false, isPaused: Bool = false, isScrubbing: Bool = false, skip: SkipFeedback? = nil) {
        self.isVisible = isVisible
        self.isPaused = isPaused
        self.isScrubbing = isScrubbing
        self.skip = skip
    }
}

/// A skip to flash on the bar. `token` changes with every skip so a repeated one pulses again.
public struct SkipFeedback: Sendable, Equatable {
    public let direction: SkipDirection
    public let token: Int
}

/// What the Menu button does next.
public enum MenuOutcome: Sendable, Equatable {
    /// The display or a scrub was dismissed: stay in the player.
    case handled
    /// Nothing left to dismiss: leave the player.
    case exit
}

/// The remote's transport: play / pause, ±10 s skips, scrubbing and when the display shows. Knows the player
/// only through `Driver`, so it is testable and the display stays free of mpv.
@MainActor
@Observable
public final class TransportController {
    public struct Driver {
        /// The position to act on and show (a pending seek already counts).
        public var position: @MainActor () -> Double
        public var duration: @MainActor () -> Double
        public var isPaused: @MainActor () -> Bool
        /// Absolute seek, already clamped.
        public var seek: @MainActor (Double) -> Void
        public var setPaused: @MainActor (Bool) -> Void

        public init(
            position: @escaping @MainActor () -> Double, duration: @escaping @MainActor () -> Double,
            isPaused: @escaping @MainActor () -> Bool, seek: @escaping @MainActor (Double) -> Void,
            setPaused: @escaping @MainActor (Bool) -> Void
        ) {
            self.position = position
            self.duration = duration
            self.isPaused = isPaused
            self.seek = seek
            self.setPaused = setPaused
        }
    }

    public private(set) var visibility = OSDVisibility()
    public private(set) var scrub: ScrubSession?
    public private(set) var skipFeedback: SkipFeedback?

    private let driver: Driver
    private let now: @MainActor () -> Date
    private var skipCount = 0

    public init(driver: Driver, now: @escaping @MainActor () -> Date = { .now }) {
        self.driver = driver
        self.now = now
    }

    public var isScrubbing: Bool { scrub != nil }

    /// Where the playhead is drawn: the scrub preview, else the playback position.
    public var displayedPosition: Double { scrub?.target ?? driver.position() }

    public var state: OSDState {
        OSDState(isVisible: visibility.isVisible, isPaused: driver.isPaused(), isScrubbing: isScrubbing, skip: skipFeedback)
    }

    // MARK: Display

    /// Any touch of the pad, swipe or button press.
    public func reveal() {
        visibility.reveal(isPlaying: !driver.isPaused() && !isScrubbing, now: now())
    }

    /// The player's pause state changed (also when it was not us who changed it).
    public func pausedChanged(_ paused: Bool) {
        if paused {
            visibility.hold()
        } else if visibility.isVisible, !isScrubbing {
            visibility.reveal(isPlaying: true, now: now())
        }
    }

    /// The inactivity timer fired.
    public func expire() {
        visibility.expire(now: now())
    }

    public func clearSkipFeedback(token: Int) {
        if skipFeedback?.token == token { skipFeedback = nil }
    }

    // MARK: Buttons

    public func playPause() {
        let paused = !driver.isPaused()
        driver.setPaused(paused)
        pausedChanged(paused)
    }

    /// Clicking the pad centre: validates a scrub, otherwise toggles pause.
    public func select() {
        if isScrubbing { commitScrub() } else { playPause() }
    }

    /// A left / right click: ±10 s, or a nudge of the scrub preview.
    public func skip(_ direction: SkipDirection) {
        if var session = scrub {
            session.nudge(direction)
            scrub = session
            return
        }
        driver.seek(TransportMath.skipTarget(from: driver.position(), direction: direction, duration: driver.duration()))
        skipCount += 1
        skipFeedback = SkipFeedback(direction: direction, token: skipCount)
        reveal()
    }

    public func menu() -> MenuOutcome {
        if isScrubbing {
            cancelScrub()
            return .handled
        }
        guard visibility.isVisible else { return .exit }
        visibility.hide()
        return .handled
    }

    // MARK: Scrubbing

    /// A finger starts moving on the pad. Paused, it grabs the playhead; playing, it only shows the display.
    public func panBegan() {
        guard driver.isPaused() else {
            reveal()
            return
        }
        var session = scrub ?? ScrubSession(origin: driver.position(), duration: driver.duration())
        session.beginPan()
        scrub = session
        visibility.hold()
    }

    /// `fraction`: travel since `panBegan()` in pad widths.
    public func pan(fraction: Double) {
        guard var session = scrub else { return }
        session.pan(fraction: fraction)
        scrub = session
    }

    /// Seeks to the preview and resumes.
    public func commitScrub() {
        guard let session = scrub else { return }
        scrub = nil
        driver.seek(session.target)
        driver.setPaused(false)
        visibility.reveal(isPlaying: true, now: now())
    }

    /// Drops the preview; the video stays paused where it was.
    public func cancelScrub() {
        scrub = nil
        visibility.hold()
    }
}
