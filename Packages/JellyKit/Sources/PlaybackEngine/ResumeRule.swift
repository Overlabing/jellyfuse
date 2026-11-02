import Foundation
import LibraryKit

/// The server's resume thresholds (`ServerConfiguration`), read from it and never hard-coded.
public struct ResumeThresholds: Sendable, Equatable {
    public var minPercent: Double
    public var maxPercent: Double
    public var minDurationSeconds: Double

    public init(minPercent: Double, maxPercent: Double, minDurationSeconds: Double) {
        self.minPercent = minPercent
        self.maxPercent = maxPercent
        self.minDurationSeconds = minDurationSeconds
    }
}

/// Replicates `UserDataManager.UpdatePlayState` locally (data-plan §5.2) so a stop is reflected at once.
public enum ResumeRule {
    private static let ticksPerSecond = 10_000_000.0

    /// `PlayCount` is not touched by the server's rule; the local approximation `max(1, playCount)` on
    /// "watched" is rectified by the server's own user data on the next load.
    public static func apply(
        to data: UserData, positionTicks: Int64, runtimeTicks: Int64?, thresholds: ResumeThresholds, now: Date
    ) -> UserData {
        var result = data
        result.lastPlayedDate = now
        guard let runtimeTicks, runtimeTicks > 0 else {
            result.playbackPositionTicks = positionTicks
            return result
        }
        let percent = Double(positionTicks) / Double(runtimeTicks) * 100
        let remainingSeconds = Double(runtimeTicks - positionTicks) / ticksPerSecond
        let runtimeSeconds = Double(runtimeTicks) / ticksPerSecond

        if percent < thresholds.minPercent {
            result.playbackPositionTicks = 0
            result.played = false
        } else if percent > thresholds.maxPercent || remainingSeconds < 1 {
            result.playbackPositionTicks = 0
            result.played = true
            result.playCount = max(1, result.playCount)
        } else if runtimeSeconds < thresholds.minDurationSeconds {
            result.playbackPositionTicks = 0
            result.played = true
            result.playCount = max(1, result.playCount)
        } else {
            result.playbackPositionTicks = positionTicks
            result.played = false
        }
        return result
    }
}
