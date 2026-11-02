import Foundation
import Testing
@testable import LibraryKit

@Suite struct JellyfinClientTests {
    private let session = Session(
        serverURL: URL(string: "https://jf.example.com")!, token: "secret-token",
        userId: "u1", userName: "Anto", deviceId: "dev"
    )

    private func queryItems(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func streamURLIsDirectStaticWithMediaSourceAndToken() throws {
        let client = JellyfinClient(session: session)
        let url = try #require(client.streamURL(itemId: "item1", mediaSourceId: "src1"))
        #expect(url.host == "jf.example.com")
        #expect(url.path == "/Videos/item1/stream")
        let query = queryItems(url)
        #expect(query["static"] == "true")
        #expect(query["mediaSourceId"] == "src1")
        #expect(query["ApiKey"] == "secret-token")
    }

    @Test func imageURLCarriesTagAndWidthAndIsNilWithoutTag() throws {
        let client = JellyfinClient(session: session)
        let url = try #require(client.imageURL(itemId: "item1", tag: "abc", maxWidth: 400))
        #expect(url.path == "/Items/item1/Images/Primary")
        let query = queryItems(url)
        #expect(query["tag"] == "abc")
        #expect(query["maxWidth"] == "400")
        #expect(client.imageURL(itemId: "item1", tag: nil) == nil)
    }

    @Test func libraryCallsRequireSignIn() async {
        let client = JellyfinClient(serverURL: session.serverURL, deviceId: "dev")
        await #expect(throws: JellyfinError.self) { try await client.latest(in: "lib") }
        await #expect(throws: JellyfinError.self) { try await client.libraries() }
    }

    @Test func progressIsWatchedFraction() {
        var data = UserData.none
        data.playbackPositionTicks = 250
        #expect(data.progress(runtimeTicks: 1000) == 0.25)
        #expect(UserData.none.progress(runtimeTicks: 1000) == nil)
        #expect(data.progress(runtimeTicks: nil) == nil)
    }
}

@Suite struct SearchParametersTests {
    @Test func searchRequestIsRecursiveOneKindWithTermAndImages() throws {
        let query = try #require(SearchQuery(" la  nuit "))
        let parameters = JellyfinClient.searchParameters(userId: "u1", query: query, kind: .series, limit: 12)
        #expect(parameters.searchTerm == "la nuit")
        #expect(parameters.isRecursive == true)
        #expect(parameters.limit == 12)
        #expect(parameters.userID == "u1")
        #expect(parameters.includeItemTypes == [.series])
        #expect(parameters.enableImageTypes == [.primary, .logo])
    }

    @Test func everyKindMapsToItsOwnItemType() {
        #expect(SearchKind.allCases.map(\.sdkType) == [.movie, .series, .episode])
    }

    @Test func searchRequiresSignIn() async throws {
        let client = JellyfinClient(serverURL: URL(string: "https://jf.example.com")!, deviceId: "dev")
        let query = try #require(SearchQuery("nuit"))
        await #expect(throws: JellyfinError.self) { try await client.search(query, kind: .movie, limit: 12) }
    }
}
