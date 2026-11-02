import Foundation
import Get
import JellyfinAPI

public enum JellyfinError: Error, LocalizedError {
    case http(Int)
    case unauthorized
    case badResponse
    case notSignedIn

    public var errorDescription: String? {
        switch self {
        case .http(401): "Credentials refused"
        case .unauthorized: "Session expired or revoked, sign in again"
        case .http(let code): "Jellyfin answered HTTP \(code)"
        case .badResponse: "Unreadable Jellyfin response"
        case .notSignedIn: "Not signed in"
        }
    }
}

/// The images of an item Jellyfuse shows.
public enum ItemImageKind: Sendable {
    case primary
    case backdrop
    case logo

    var sdkType: ImageType {
        switch self {
        case .primary: .primary
        case .backdrop: .backdrop
        case .logo: .logo
        }
    }
}

/// The Jellyfin client: a thin facade over the official SDK. Every request goes through the SDK.
/// One instance per session; the SDK sends the `Authorization: MediaBrowser ...` header.
public actor JellyfinClient {
    public static let clientName = "Jellyfuse"
    public static let clientVersion = "0.1.0"

    /// Quick Connect progress, as produced by the SDK.
    public typealias QuickConnectEvent = QuickConnect.Event

    private let sdk: JellyfinAPI.JellyfinClient
    public nonisolated let serverURL: URL
    private let deviceId: String
    private var userId: String?
    private let hasToken: Bool
    private let token: String?
    private let onUnauthorized: (@Sendable () -> Void)?

    /// Unauthenticated client, used to sign in.
    public init(serverURL: URL, deviceId: String, deviceName: String = "Apple TV", urlSession: URLSession = .shared) {
        self.init(serverURL: serverURL, deviceId: deviceId, deviceName: deviceName, token: nil, userId: nil, configuration: urlSession.configuration, onUnauthorized: nil)
    }

    /// `onUnauthorized` fires when a signed request is answered 401: the server revoked the token.
    /// `deviceName` is how the server lists this device; the app passes the platform's own name.
    public init(session: Session, deviceName: String = "Apple TV", urlSession: URLSession = .shared, onUnauthorized: (@Sendable () -> Void)? = nil) {
        self.init(serverURL: session.serverURL, deviceId: session.deviceId, deviceName: deviceName, token: session.token, userId: session.userId, configuration: urlSession.configuration, onUnauthorized: onUnauthorized)
    }

    private init(serverURL: URL, deviceId: String, deviceName: String, token: String?, userId: String?, configuration: URLSessionConfiguration, onUnauthorized: (@Sendable () -> Void)?) {
        self.serverURL = serverURL
        self.deviceId = deviceId
        self.userId = userId
        self.hasToken = token != nil
        self.token = token
        self.onUnauthorized = onUnauthorized
        self.sdk = JellyfinAPI.JellyfinClient(
            configuration: .init(
                url: serverURL,
                accessToken: token,
                client: Self.clientName,
                deviceName: deviceName,
                deviceID: deviceId,
                version: Self.clientVersion
            ),
            sessionConfiguration: configuration
        )
    }

    // MARK: Auth

    public func authenticate(username: String, password: String) async throws -> Session {
        let result: AuthenticationResult
        do {
            result = try await call { try await self.sdk.signIn(username: username, password: password) }
        } catch JellyfinError.unauthorized {
            // No token yet: a 401 here is a wrong password, not a revocation.
            throw JellyfinError.http(401)
        }
        return try session(from: result, fallbackName: username)
    }

    /// Starts a Quick Connect flow: yields `.polling(code:)` (to show on screen), then `.authenticated(secret:)`.
    /// Finish with `authenticate(quickConnectSecret:)`.
    public nonisolated func quickConnect(pollInterval: Int = 5) -> AsyncThrowingStream<QuickConnectEvent, Error> {
        sdk.quickConnect.connect(poll: pollInterval)
    }

    public func authenticate(quickConnectSecret: String) async throws -> Session {
        let result = try await call { try await self.sdk.signIn(quickConnectSecret: quickConnectSecret) }
        return try session(from: result, fallbackName: "")
    }

    /// Images the shelves use: the poster/landscape art and the billboard's title logo.
    private static let shelfImageTypes: [ImageType] = [.primary, .logo]

    // MARK: Library

    /// The user's views reduced to the video libraries (`/UserViews`), in the server's order.
    public func libraries() async throws -> [Library] {
        let userId = try requireUserId()
        let request = Paths.getUserViews(parameters: .init(userID: userId))
        let result = try await call { try await self.sdk.send(request).value }
        return Library.videoLibraries(from: result.items ?? [])
    }

    public func latest(in libraryId: String, limit: Int = 20) async throws -> [LibraryEntry] {
        let userId = try requireUserId()
        let request = Paths.getLatestMedia(parameters: .init(userID: userId, parentID: libraryId, enableImageTypes: Self.shelfImageTypes, limit: limit))
        let result = try await call { try await self.sdk.send(request).value }
        return result.compactMap(LibraryEntry.init(dto:))
    }

    public func recentlyAdded(in libraryId: String, limit: Int = 100) async throws -> [LibraryEntry] {
        let userId = try requireUserId()
        let request = Paths.getItems(parameters: .init(
            userID: userId, limit: limit, isRecursive: true, sortOrder: [.descending],
            parentID: libraryId, includeItemTypes: [.movie, .series], sortBy: [.dateCreated],
            enableImageTypes: Self.shelfImageTypes
        ))
        let result = try await call { try await self.sdk.send(request).value }
        return (result.items ?? []).compactMap(LibraryEntry.init(dto:))
    }

    public func resume(limit: Int = 20) async throws -> [LibraryEntry] {
        let userId = try requireUserId()
        let request = Paths.getResumeItems(parameters: .init(userID: userId, limit: limit, mediaTypes: [.video], enableImageTypes: Self.shelfImageTypes))
        let result = try await call { try await self.sdk.send(request).value }
        return (result.items ?? []).compactMap(LibraryEntry.init(dto:))
    }

    public func nextUp(limit: Int = 20) async throws -> [LibraryEntry] {
        let userId = try requireUserId()
        let request = Paths.getNextUp(parameters: .init(userID: userId, limit: limit, enableImageTypes: Self.shelfImageTypes))
        let result = try await call { try await self.sdk.send(request).value }
        return (result.items ?? []).compactMap(LibraryEntry.init(dto:))
    }

    public func detail(of itemId: String) async throws -> (detail: ItemDetail, userData: UserData) {
        let userId = try requireUserId()
        let request = Paths.getItem(itemID: itemId, userID: userId)
        let dto = try await call { try await self.sdk.send(request).value }
        guard let detail = ItemDetail(dto: dto) else { throw JellyfinError.badResponse }
        return (detail, dto.userData.map(UserData.init(dto:)) ?? .none)
    }

    public func seasons(of seriesId: String) async throws -> [LibraryEntry] {
        let userId = try requireUserId()
        let request = Paths.getSeasons(seriesID: seriesId, parameters: .init(userID: userId))
        let result = try await call { try await self.sdk.send(request).value }
        return (result.items ?? []).compactMap(LibraryEntry.init(dto:))
    }

    public func episodes(of seriesId: String) async throws -> [LibraryEntry] {
        let userId = try requireUserId()
        let request = Paths.getEpisodes(seriesID: seriesId, parameters: .init(userID: userId, enableUserData: true))
        let result = try await call { try await self.sdk.send(request).value }
        return (result.items ?? []).compactMap(LibraryEntry.init(dto:))
    }

    public func setFavorite(_ isFavorite: Bool, for itemId: String) async throws {
        let userId = try requireUserId()
        let request = isFavorite
            ? Paths.markFavoriteItem(itemID: itemId, userID: userId)
            : Paths.unmarkFavoriteItem(itemID: itemId, userID: userId)
        _ = try await call { try await self.sdk.send(request).value }
    }

    public func setPlayed(_ isPlayed: Bool, for itemId: String) async throws {
        let userId = try requireUserId()
        let request = isPlayed
            ? Paths.markPlayedItem(itemID: itemId, userID: userId)
            : Paths.markUnplayedItem(itemID: itemId, userID: userId)
        _ = try await call { try await self.sdk.send(request).value }
    }

    /// Unauthenticated reachability probe (`/System/Info/Public`), 5 s budget, no retry.
    public func ping() async -> Bool {
        let request = Paths.getPublicSystemInfo
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { (try? await self.sdk.send(request).value) != nil }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    // MARK: URLs

    public nonisolated func imageURL(itemId: String, tag: String?, maxWidth: Int = 600) -> URL? {
        imageURL(itemId: itemId, kind: .primary, tag: tag, maxWidth: maxWidth)
    }

    /// `/Items/{id}/Images/{type}?tag=...`: the tag makes the URL cacheable forever and doubles as "has this image".
    public nonisolated func imageURL(itemId: String, kind: ItemImageKind, tag: String?, maxWidth: Int) -> URL? {
        guard let tag else { return nil }
        let request = Paths.getItemImage(
            itemID: itemId, imageType: kind.sdkType.rawValue,
            parameters: .init(maxWidth: maxWidth, quality: 90, tag: tag)
        )
        return sdk.url(with: request)
    }

    /// Direct (`static=true`) file URL: no transcode, the server streams the original container.
    public nonisolated func streamURL(itemId: String, mediaSourceId: String) -> URL? {
        let request = Paths.getVideoStream(
            itemID: itemId,
            parameters: .init(isStatic: true, mediaSourceID: mediaSourceId)
        )
        return sdk.url(with: request, queryAPIKey: true)
    }

    // MARK: Generic requests (package-internal, for sibling targets such as PlaybackEngine)

    /// Sends any SDK request through the same error mapping (401 handling included).
    package func perform<T: Decodable & Sendable>(_ request: Request<T>) async throws -> T {
        try await call { try await self.sdk.send(request).value }
    }

    package func perform(_ request: Request<Void>) async throws {
        try await call { try await self.sdk.send(request).value }
    }

    /// URL of an SDK request carrying `api_key`: for consumers that cannot set headers (mpv).
    /// Never log or persist the result.
    package nonisolated func authenticatedURL(for request: Request<some Any>) -> URL? {
        sdk.url(with: request, queryAPIKey: true)
    }

    /// Resolves a server-relative path (e.g. a `TranscodingUrl`) against the server, adding `api_key`
    /// (as the SDK spells it, `ApiKey`) when the path does not carry one. Never log or persist the result.
    package nonisolated func authenticatedURL(path: String) -> URL? {
        var base = serverURL.absoluteString
        if base.hasSuffix("/") { base.removeLast() }
        guard var components = URLComponents(string: base + (path.hasPrefix("/") ? path : "/" + path)) else { return nil }
        var query = components.queryItems ?? []
        if let token, !query.contains(where: { ["apikey", "api_key"].contains($0.name.lowercased()) }) {
            query.append(URLQueryItem(name: "ApiKey", value: token))
        }
        components.queryItems = query.isEmpty ? nil : query
        return components.url
    }

    // MARK: Plumbing

    package func currentUserId() throws -> String { try requireUserId() }

    private func requireUserId() throws -> String {
        guard let userId else { throw JellyfinError.notSignedIn }
        return userId
    }

    private func session(from result: AuthenticationResult, fallbackName: String) throws -> Session {
        guard let token = result.accessToken, let user = result.user, let id = user.id else { throw JellyfinError.badResponse }
        userId = id
        return Session(serverURL: serverURL, token: token, userId: id, userName: user.name ?? fallbackName, deviceId: deviceId)
    }

    private func call<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as APIError {
            if case .unacceptableStatusCode(let code) = error {
                if code == 401 {
                    if hasToken { onUnauthorized?() }
                    throw JellyfinError.unauthorized
                }
                throw JellyfinError.http(code)
            }
            throw JellyfinError.badResponse
        } catch is DecodingError {
            throw JellyfinError.badResponse
        }
    }
}
