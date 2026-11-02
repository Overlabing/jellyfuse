import Foundation
import LibraryKit

/// What the Réglages screen shows about the signed-in account and the build. Pure, so it is testable.
public struct AccountSummary: Sendable, Equatable {
    public let serverAddress: String
    public let userName: String

    public init(_ session: Session) {
        serverAddress = session.serverURL.absoluteString
        userName = session.userName
    }
}

public enum AppVersion {
    /// `0.1 (1)` from `CFBundleShortVersionString` and `CFBundleVersion`; either may be missing.
    public static func display(_ info: [String: Any]?) -> String {
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (version, build) {
        case let (version?, build?): return "\(version) (\(build))"
        case let (version?, nil): return version
        case let (nil, build?): return "(\(build))"
        case (nil, nil): return "—"
        }
    }
}
