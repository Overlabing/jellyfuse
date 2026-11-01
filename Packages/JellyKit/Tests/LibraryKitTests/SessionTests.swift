import Foundation
import Testing
@testable import LibraryKit

@Suite struct SessionTests {
    private func session(server: String = "https://jf.example.com", user: String = "u1") -> Session {
        Session(serverURL: URL(string: server)!, token: "tok", userId: user, userName: "Anto", deviceId: "dev")
    }

    @Test func libraryOwnerCombinesServerAndUser() {
        #expect(session().libraryOwner == "https://jf.example.com|u1")
    }

    @Test func libraryOwnerDiffersPerUserAndServer() {
        #expect(session().libraryOwner != session(user: "u2").libraryOwner)
        #expect(session().libraryOwner != session(server: "https://other.example.com").libraryOwner)
    }

    @Test func sessionRoundTripsThroughJSON() throws {
        let original = session()
        let decoded = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}
