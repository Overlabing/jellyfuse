import JellyfinAPI

/// The slice of a Jellyfin item the home shelves need.
public struct MediaItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let seriesName: String?
    public let primaryImageTag: String?
    public let runtimeTicks: Int64?
    public let playbackPositionTicks: Int64?

    public init(
        id: String, name: String, seriesName: String? = nil, primaryImageTag: String? = nil,
        runtimeTicks: Int64? = nil, playbackPositionTicks: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.seriesName = seriesName
        self.primaryImageTag = primaryImageTag
        self.runtimeTicks = runtimeTicks
        self.playbackPositionTicks = playbackPositionTicks
    }

    /// Watched fraction in 0...1, nil when the item has no progress.
    public var progress: Double? {
        guard let runtime = runtimeTicks, runtime > 0, let position = playbackPositionTicks, position > 0 else { return nil }
        return min(1, Double(position) / Double(runtime))
    }
}

extension MediaItem {
    init?(dto: BaseItemDto) {
        guard let id = dto.id else { return nil }
        self.init(
            id: id,
            name: dto.name ?? "",
            seriesName: dto.seriesName,
            primaryImageTag: dto.imageTags?["Primary"],
            runtimeTicks: dto.runTimeTicks.map(Int64.init),
            playbackPositionTicks: dto.userData?.playbackPositionTicks.map(Int64.init)
        )
    }
}
