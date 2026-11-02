import Foundation
import Testing
@testable import LibraryKit

@Suite struct UserFacingErrorTests {
    @Test func classifiesTransportHttpAndAuthFailures() {
        #expect(UserFacingError(URLError(.notConnectedToInternet)) == .network)
        #expect(UserFacingError(URLError(.cancelled)) == .other)
        #expect(UserFacingError(JellyfinError.unauthorized) == .unauthorized)
        #expect(UserFacingError(JellyfinError.http(401)) == .unauthorized)
        #expect(UserFacingError(JellyfinError.http(503)) == .server(503))
        #expect(UserFacingError(JellyfinError.badResponse) == .unreadable)
        #expect(UserFacingError(CancellationError()) == .other)
    }
}
