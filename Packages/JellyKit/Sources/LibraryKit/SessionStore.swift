import Foundation
import Security

public enum SessionStoreError: Error, LocalizedError {
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .keychain(let status): "Keychain unavailable (\(status))"
        }
    }
}

/// Keychain-backed session and stable device id.
public enum SessionStore {
    /// Tests point it elsewhere so they never touch the app's own items.
    nonisolated(unsafe) static var service = "dev.antonin.jellytv"
    private static let account = "session"
    private static let deviceAccount = "deviceId"

    public static func load() -> Session? {
        guard let data = read(account) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    public static func save(_ session: Session) throws {
        let status = write(account, try JSONEncoder().encode(session))
        guard status == errSecSuccess else { throw SessionStoreError.keychain(status) }
    }

    public static func clear() {
        SecItemDelete(query(account) as CFDictionary)
    }

    /// Stable per-install device id: Jellyfin attributes the token to it.
    public static func deviceId() -> String {
        if let data = read(deviceAccount), let id = String(data: data, encoding: .utf8) { return id }
        let id = UUID().uuidString
        write(deviceAccount, Data(id.utf8))
        return id
    }

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func read(_ account: String) -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    @discardableResult
    private static func write(_ account: String, _ data: Data) -> OSStatus {
        SecItemDelete(query(account) as CFDictionary)
        var q = query(account)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(q as CFDictionary, nil)
    }
}
