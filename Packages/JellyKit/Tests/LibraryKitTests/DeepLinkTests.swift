import Foundation
import Testing
@testable import LibraryKit

@Suite struct DeepLinkTests {
    @Test func parsesDetail() {
        #expect(DeepLink(url: URL(string: "jellyfuse://detail/abc123")!) == .detail(id: "abc123"))
    }

    @Test func parsesPlayWithPositionAndTitle() {
        let url = URL(string: "jellyfuse://play/abc?t=90&title=Un%20film")!
        #expect(DeepLink(url: url) == .play(id: "abc", title: "Un film", resumeSeconds: 90))
    }

    @Test func playWithoutPositionStartsAtZero() {
        #expect(DeepLink(url: URL(string: "jellyfuse://play/abc")!) == .play(id: "abc", title: "", resumeSeconds: 0))
    }

    @Test func rejectsForeignSchemesUnknownHostsAndMissingIds() {
        #expect(DeepLink(url: URL(string: "https://detail/abc")!) == nil)
        #expect(DeepLink(url: URL(string: "jellyfuse://settings/abc")!) == nil)
        #expect(DeepLink(url: URL(string: "jellyfuse://detail")!) == nil)
    }

    @Test func urlRoundTrips() throws {
        for link in [DeepLink.detail(id: "x1"), .play(id: "x2", title: "L'été & co", resumeSeconds: 1234)] {
            #expect(DeepLink(url: try #require(link.url)) == link)
        }
    }
}
