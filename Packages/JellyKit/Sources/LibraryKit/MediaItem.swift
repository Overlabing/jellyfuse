import JellyfinAPI

/// Quasi-immutable metadata of a Jellyfin item. Watched state, progress and favorite live in
/// `UserData`, stored once per item id (data-plan D2).
public struct MediaItem: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let name: String
    public let seriesName: String?
    public let primaryImageTag: String?
    public let runtimeTicks: Int64?

    public init(
        id: String, name: String, seriesName: String? = nil, primaryImageTag: String? = nil,
        runtimeTicks: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.seriesName = seriesName
        self.primaryImageTag = primaryImageTag
        self.runtimeTicks = runtimeTicks
    }
}

/// An item as the server returns it: metadata plus the user's own data, ready to be split into the store.
public struct LibraryEntry: Sendable, Equatable {
    public let item: MediaItem
    public let userData: UserData

    public init(item: MediaItem, userData: UserData = .none) {
        self.item = item
        self.userData = userData
    }
}

extension LibraryEntry {
    init?(dto: BaseItemDto) {
        guard let id = dto.id else { return nil }
        self.init(
            item: MediaItem(
                id: id,
                name: dto.name ?? "",
                seriesName: dto.seriesName,
                primaryImageTag: dto.imageTags?["Primary"],
                runtimeTicks: dto.runTimeTicks.map(Int64.init)
            ),
            userData: dto.userData.map(UserData.init(dto:)) ?? .none
        )
    }
}
