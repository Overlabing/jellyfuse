import Foundation

/// A signed-in Jellyfin user on this device. Jellyfin tokens are device
/// records: they do not expire, the server revokes them.
public struct Session: Codable, Sendable, Equatable {
    public let serverURL: URL
    public let token: String
    public let userId: String
    public let userName: String
    public let deviceId: String

    /// Identifies whose library and downloads the device holds: same server and user, same cache.
    public var libraryOwner: String { "\(serverURL.absoluteString)|\(userId)" }

    public init(serverURL: URL, token: String, userId: String, userName: String, deviceId: String) {
        self.serverURL = serverURL
        self.token = token
        self.userId = userId
        self.userName = userName
        self.deviceId = deviceId
    }
}
