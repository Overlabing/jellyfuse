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

/// The Jellyfin client: a thin facade over the official SDK. Every request goes through the SDK.
/// One instance per session; the SDK sends the `Authorization: MediaBrowser ...` header.
public actor JellyfinClient {
    public static let clientName = "Jellyfuse"
    public static let clientVersion = "0.1.0"

    /// Quick Connect progress, as produced by the SDK.
    public typealias QuickConnectEvent = QuickConnect.Event

    private let sdk: JellyfinAPI.JellyfinClient
    private let serverURL: URL
    private let deviceId: String
    private var userId: String?
    private let hasToken: Bool
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

    // MARK: Library

    public func latestMedia(limit: Int = 20) async throws -> [LibraryEntry] {
        let userId = try requireUserId()
        let request = Paths.getLatestMedia(parameters: .init(userID: userId, limit: limit))
        let result = try await call { try await self.sdk.send(request).value }
        return result.compactMap(LibraryEntry.init(dto:))
    }

    public func resume(limit: Int = 20) async throws -> [LibraryEntry] {
        let userId = try requireUserId()
        let request = Paths.getResumeItems(parameters: .init(userID: userId, limit: limit, mediaTypes: [.video]))
        let result = try await call { try await self.sdk.send(request).value }
        return (result.items ?? []).compactMap(LibraryEntry.init(dto:))
    }

    public func nextUp(limit: Int = 20) async throws -> [LibraryEntry] {
        let userId = try requireUserId()
        let request = Paths.getNextUp(parameters: .init(userID: userId, limit: limit))
        let result = try await call { try await self.sdk.send(request).value }
        return (result.items ?? []).compactMap(LibraryEntry.init(dto:))
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
        guard let tag else { return nil }
        let request = Paths.getItemImage(
            itemID: itemId, imageType: ImageType.primary.rawValue,
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

    // MARK: Plumbing

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
