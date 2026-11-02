import Foundation

/// What a failure means to the user, whatever layer raised it. The UI shows a banner for
/// `.network`, restarts sign-in on `.unauthorized` and an alert for the rest.
public enum UserFacingError: Error, Equatable, Sendable {
    case network
    case unauthorized
    case server(Int)
    case unreadable
    case other

    public init(_ error: any Error) {
        if let facing = error as? UserFacingError {
            self = facing
        } else if Self.isNetwork(error) {
            self = .network
        } else if let jellyfin = error as? JellyfinError {
            switch jellyfin {
            case .unauthorized, .notSignedIn: self = .unauthorized
            case .http(let code): self = code == 401 ? .unauthorized : .server(code)
            case .badResponse: self = .unreadable
            }
        } else {
            self = .other
        }
    }

    /// Transport failures: no connection, timeout, host unreachable. Worth retrying, never an item problem.
    public static func isNetwork(_ error: any Error) -> Bool {
        guard let url = error as? URLError else { return false }
        return url.code != .cancelled
    }
}
