import Foundation
import Testing
@testable import HomePresentation
import DesignSystem

@Suite struct PlayPromptTests {
    @Test func noPromptWithoutResumePosition() {
        #expect(PlayPrompt(PlayTarget(id: "a", title: "A", resumeSeconds: 0)) == nil)
    }

    @Test func promptOffersFormattedPositionAndRestart() throws {
        let target = PlayTarget(id: "a", title: "White Collar", resumeSeconds: 12 * 60 + 40)
        let prompt = try #require(PlayPrompt(target))
        #expect(prompt.resumeLabel == "Reprendre à 0 h 12")
        #expect(prompt.resume == target)
        #expect(prompt.restart == PlayTarget(id: "a", title: "White Collar", resumeSeconds: 0))
    }

    @Test func positionFormat() {
        #expect(MediaFormat.position(seconds: 0) == nil)
        #expect(MediaFormat.position(seconds: 3_900) == "1 h 05")
        #expect(MediaFormat.position(seconds: 59) == "0 h 00")
    }

    @Test func pollsOnlyWhileHomeIsVisible() {
        #expect(HomeRefreshPolicy.shouldPoll(sceneIsActive: true, homeIsVisible: true, playerIsOpen: false))
        #expect(!HomeRefreshPolicy.shouldPoll(sceneIsActive: false, homeIsVisible: true, playerIsOpen: false))
        #expect(!HomeRefreshPolicy.shouldPoll(sceneIsActive: true, homeIsVisible: false, playerIsOpen: false))
        #expect(!HomeRefreshPolicy.shouldPoll(sceneIsActive: true, homeIsVisible: true, playerIsOpen: true))
    }
}
