import Foundation

/// A third-party component the app ships or links, with where its license text comes from.
public struct LicenseEntry: Codable, Sendable, Equatable, Identifiable {
    public enum Group: String, Codable, Sendable, CaseIterable {
        /// This app itself.
        case app
        /// The playback stack: MPVKit, mpv, FFmpeg and the libraries it is built from.
        case playback
        /// The Jellyfin SDK and the Swift packages it brings.
        case sdk
    }

    public let id: String
    public let name: String
    public let group: Group
    public let url: String
    public let version: String?
    /// Human-readable license name. Nil when it was not verified: the screen then says « voir le dépôt ».
    public let license: String?
    /// File under `LicenseData/texts`, verbatim from upstream. Nil when no text could be sourced.
    public let textFile: String?
    /// Where `textFile` was taken from (upstream URL or resolved package).
    public let textSource: String?
    public let note: String?
}

/// `LicenseData/licenses.json`: the list behind the Licences screen.
public struct LicenseManifest: Codable, Sendable, Equatable {
    public let version: Int
    public let entries: [LicenseEntry]

    public static func decode(_ data: Data) throws -> LicenseManifest {
        try JSONDecoder().decode(LicenseManifest.self, from: data)
    }

    public func entries(in group: LicenseEntry.Group) -> [LicenseEntry] {
        entries.filter { $0.group == group }
    }
}

/// Reads the bundled manifest and texts.
public struct LicenseCatalog: Sendable {
    public let manifest: LicenseManifest
    private let textsDirectory: URL?

    public init(manifest: LicenseManifest, textsDirectory: URL?) {
        self.manifest = manifest
        self.textsDirectory = textsDirectory
    }

    /// The manifest shipped in this package's resources.
    public static func bundled() throws -> LicenseCatalog {
        guard let url = Bundle.module.url(forResource: "licenses", withExtension: "json", subdirectory: "LicenseData") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let manifest = try LicenseManifest.decode(Data(contentsOf: url))
        let texts = Bundle.module.url(forResource: "texts", withExtension: nil, subdirectory: "LicenseData")
        return LicenseCatalog(manifest: manifest, textsDirectory: texts)
    }

    /// The full text, or nil when the entry has none (the screen then points at the repository).
    public func text(for entry: LicenseEntry) -> String? {
        guard let file = entry.textFile, let textsDirectory else { return nil }
        return try? String(contentsOf: textsDirectory.appendingPathComponent(file), encoding: .utf8)
    }
}
