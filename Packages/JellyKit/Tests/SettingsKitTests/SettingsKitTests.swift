import Foundation
import LibraryKit
import Testing
@testable import SettingsKit

@Suite struct LicenseManifestTests {
    @Test func decodesAnEntryWithAndWithoutText() throws {
        let json = """
        {"version":1,"entries":[
          {"id":"a","name":"A","group":"playback","url":"https://x","license":"MIT","textFile":"a.txt"},
          {"id":"b","name":"B","group":"sdk","url":"https://y"}
        ]}
        """
        let manifest = try LicenseManifest.decode(Data(json.utf8))
        #expect(manifest.entries.count == 2)
        #expect(manifest.entries[0].textFile == "a.txt")
        #expect(manifest.entries[1].license == nil)
        #expect(manifest.entries(in: .sdk).map(\.id) == ["b"])
    }

    @Test func rejectsAnUnknownGroup() {
        let json = #"{"version":1,"entries":[{"id":"a","name":"A","group":"zzz","url":"u"}]}"#
        #expect(throws: (any Error).self) { try LicenseManifest.decode(Data(json.utf8)) }
    }

    @Test func entryWithoutTextFileHasNoText() {
        let manifest = LicenseManifest(version: 1, entries: [])
        let catalog = LicenseCatalog(manifest: manifest, textsDirectory: nil)
        let entry = try! LicenseManifest.decode(Data(#"{"version":1,"entries":[{"id":"a","name":"A","group":"app","url":"u"}]}"#.utf8)).entries[0]
        #expect(catalog.text(for: entry) == nil)
    }
}

@Suite struct BundledLicensesTests {
    @Test func idsAreUniqueAndEveryTextFileIsShippedAndNotEmpty() throws {
        let catalog = try LicenseCatalog.bundled()
        let ids = catalog.manifest.entries.map(\.id)
        #expect(Set(ids).count == ids.count)
        for entry in catalog.manifest.entries where entry.textFile != nil {
            let text = catalog.text(for: entry)
            #expect(text?.isEmpty == false, "missing text for \(entry.id)")
        }
    }

    @Test func entriesWithoutTextDoNotInventALicense() throws {
        // An entry with neither a text nor a verified license must say so (« voir le dépôt »), never carry a made-up name.
        let catalog = try LicenseCatalog.bundled()
        let unverified = catalog.manifest.entries.first { $0.id == "libbluray" }
        #expect(unverified?.license == nil)
        #expect(unverified?.textFile == nil)
    }

    @Test func listsTheLGPLStackAndTheAppItself() throws {
        let ids = Set(try LicenseCatalog.bundled().manifest.entries.map(\.id))
        for required in ["jellyfuse", "mpvkit", "mpv", "ffmpeg", "libplacebo", "libass", "moltenvk", "dav1d", "jellyfin-sdk-swift"] {
            #expect(ids.contains(required))
        }
    }

    @Test func noGPLOnlyComponentIsListed() throws {
        let entries = try LicenseCatalog.bundled().manifest.entries
        #expect(!entries.contains { $0.id == "libsmbclient" || $0.name.contains("-GPL") })
    }
}

@Suite struct AboutInfoTests {
    @Test func accountSummaryShowsServerAndUser() {
        let session = Session(
            serverURL: URL(string: "http://jelly.lan:8096")!, token: "t", userId: "u", userName: "Antonin", deviceId: "d"
        )
        let summary = AccountSummary(session)
        #expect(summary.serverAddress == "http://jelly.lan:8096")
        #expect(summary.userName == "Antonin")
    }

    @Test func versionDisplay() {
        #expect(AppVersion.display(["CFBundleShortVersionString": "0.1", "CFBundleVersion": "7"]) == "0.1 (7)")
        #expect(AppVersion.display(["CFBundleShortVersionString": "0.1"]) == "0.1")
        #expect(AppVersion.display(nil) == "—")
    }
}
