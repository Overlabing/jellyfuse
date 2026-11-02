import Foundation
import JellyfinAPI

/// The per-user state of an item: watched, resume position, favorite. The single source of truth:
/// lists store ids only, so one patch here updates every shelf (data-plan D2).
public struct UserData: Sendable, Equatable, Codable {
    public var played: Bool
    public var playbackPositionTicks: Int64
    public var playCount: Int
    public var isFavorite: Bool
    public var lastPlayedDate: Date?

    public static let none = UserData(played: false, playbackPositionTicks: 0, playCount: 0, isFavorite: false, lastPlayedDate: nil)

    public init(played: Bool, playbackPositionTicks: Int64, playCount: Int, isFavorite: Bool, lastPlayedDate: Date?) {
        self.played = played
        self.playbackPositionTicks = playbackPositionTicks
        self.playCount = playCount
        self.isFavorite = isFavorite
        self.lastPlayedDate = lastPlayedDate
    }

    /// Watched fraction in 0...1, nil when there is no progress to show.
    public func progress(runtimeTicks: Int64?) -> Double? {
        guard let runtime = runtimeTicks, runtime > 0, playbackPositionTicks > 0 else { return nil }
        return min(1, Double(playbackPositionTicks) / Double(runtime))
    }
}

extension UserData {
    init(dto: UserItemDataDto) {
        self.init(
            played: dto.isPlayed ?? false,
            playbackPositionTicks: Int64(dto.playbackPositionTicks ?? 0),
            playCount: dto.playCount ?? 0,
            isFavorite: dto.isFavorite ?? false,
            lastPlayedDate: dto.lastPlayedDate
        )
    }
}
