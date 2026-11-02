import Foundation
import JellyfinAPI
import LibraryKit

/// What the reporter needs from the network.
public protocol PlaybackReportingAPI: Sendable {
    func reportStart(_ info: PlaybackStateInfo) async throws
    func reportProgress(_ info: PlaybackStateInfo) async throws
    func reportStopped(_ info: PlaybackStopInfo) async throws
}

extension LibraryKit.JellyfinClient: PlaybackReportingAPI {
    public func reportStart(_ info: PlaybackStateInfo) async throws {
        try await perform(Paths.reportPlaybackStart(info))
    }

    public func reportProgress(_ info: PlaybackStateInfo) async throws {
        try await perform(Paths.reportPlaybackProgress(info))
    }

    public func reportStopped(_ info: PlaybackStopInfo) async throws {
        try await perform(Paths.reportPlaybackStopped(info))
    }

    /// The server's resume thresholds, nil when it does not state them (data-plan §5.2: read, never guessed).
    public func resumeThresholds() async throws -> ResumeThresholds? {
        let configuration = try await perform(Paths.getConfiguration)
        guard let minPct = configuration.minResumePct, let maxPct = configuration.maxResumePct,
              let minDuration = configuration.minResumeDurationSeconds else { return nil }
        return ResumeThresholds(minPercent: Double(minPct), maxPercent: Double(maxPct), minDurationSeconds: Double(minDuration))
    }
}
