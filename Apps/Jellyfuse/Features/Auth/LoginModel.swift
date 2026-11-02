import Foundation
import LibraryKit
import Observation

/// Sign-in flow: server address, then Quick Connect (falls back to password).
@MainActor
@Observable
final class LoginModel {
    enum Step: Equatable {
        case server
        case quickConnect
        case password
    }

    private(set) var step: Step = .server
    var serverText = ""
    var userName = ""
    var password = ""
    private(set) var code: String?
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var serverURL: URL?

    private let onSignedIn: @MainActor (Session) -> Void
    private var client: JellyfinClient?
    private var quickConnectTask: Task<Void, Never>?

    init(onSignedIn: @escaping @MainActor (Session) -> Void) {
        self.onSignedIn = onSignedIn
    }

    /// Display host for the footer, e.g. `salon.local`.
    var serverHost: String? { serverURL?.host() }

    /// Quick Connect sign-in link, encoded in the QR code.
    var quickConnectLink: URL? { serverURL?.appending(path: "web/#/quickconnect") }

    func connect() async {
        let candidates = Self.candidates(serverText)
        guard !candidates.isEmpty else {
            errorMessage = String(localized: "Adresse invalide.")
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        // Probe every candidate in parallel; among the ones that answer, HTTPS wins.
        let deviceId = SessionStore.deviceId()
        let reachable = await withTaskGroup(of: (Int, JellyfinClient)?.self) { group in
            for (rank, url) in candidates.enumerated() {
                group.addTask { @Sendable in
                    let candidate = JellyfinClient(serverURL: url, deviceId: deviceId)
                    return await candidate.ping() ? (rank, candidate) : nil
                }
            }
            var best: (Int, JellyfinClient)?
            for await hit in group {
                guard let hit else { continue }
                if best == nil || hit.0 < best!.0 { best = hit }
                if hit.0 == 0 { group.cancelAll() }
            }
            return best?.1
        }
        guard let reachable else {
            errorMessage = String(localized: "Serveur injoignable.")
            return
        }
        client = reachable
        serverURL = reachable.serverURL
        startQuickConnect()
    }

    func changeServer() {
        quickConnectTask?.cancel()
        code = nil
        errorMessage = nil
        step = .server
    }

    func usePassword() {
        quickConnectTask?.cancel()
        code = nil
        errorMessage = nil
        step = .password
    }

    func submitPassword() async {
        guard let client else { return }
        isBusy = true
        errorMessage = nil
        do {
            onSignedIn(try await client.authenticate(username: userName, password: password))
        } catch {
            errorMessage = Self.message(for: error)
        }
        isBusy = false
    }

    private func startQuickConnect() {
        guard let client else { return }
        step = .quickConnect
        quickConnectTask?.cancel()
        quickConnectTask = Task {
            do {
                for try await event in client.quickConnect() {
                    switch event {
                    case .polling(let code):
                        self.code = code
                    case .authenticated(let secret):
                        onSignedIn(try await client.authenticate(quickConnectSecret: secret))
                        return
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                // Quick Connect disabled or expired: the password form always works.
                self.step = .password
            }
        }
    }

    /// Without a scheme, candidates to probe in order: HTTPS first (public hostnames), then HTTP
    /// (LAN servers, `.local`, raw IPs, explicit ports). With a scheme, that URL only.
    static func candidates(_ text: String) -> [URL] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let raws = trimmed.contains("://") ? [trimmed] : ["https://\(trimmed)", "http://\(trimmed)"]
        return raws.compactMap { raw in
            guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https", url.host() != nil
            else { return nil }
            return url
        }
    }

    private static func message(for error: any Error) -> String {
        switch UserFacingError(error) {
        case .network: String(localized: "Serveur injoignable.")
        case .unauthorized: String(localized: "Nom ou mot de passe incorrect.")
        case .server, .unreadable, .other: String(localized: "Connexion impossible.")
        }
    }
}
