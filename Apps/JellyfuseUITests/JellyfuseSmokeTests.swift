import XCTest

/// Smoke test on the tvOS simulator: launch -> Home shows its billboard -> Movies -> back to Home.
///
/// Needs a simulator where the app is already signed in (the session lives in the Keychain and survives a
/// reinstall) and a reachable Jellyfin server; without a session the test is skipped, not failed.
/// Runs in English so it also exercises the English catalog.
@MainActor
final class JellyfuseSmokeTests: XCTestCase {
    private let app = XCUIApplication()
    private let remote = XCUIRemote.shared

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    func testHomeShowsBillboardThenMoviesThenBackHome() throws {
        let play = app.buttons["home.billboard.play"]
        let tabs = app.tabBars.firstMatch

        // 1. Home: the billboard's primary button is the first focus.
        if !play.waitForExistence(timeout: 45) {
            if app.buttons["Continue"].exists || app.textFields.firstMatch.exists {
                throw XCTSkip("No stored session on this simulator: sign in once, then rerun.")
            }
            XCTFail("The Home billboard did not appear")
        }
        XCTAssertTrue(play.hasFocus, "The billboard's Play button should hold the initial focus")

        // 2. Up to the tab bar, right to Movies (the selection follows the focus).
        remote.press(.up)
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        remote.press(.right)
        let filters = app.buttons["library.filters"]
        XCTAssertTrue(filters.waitForExistence(timeout: 20), "The Movies tab should show its Filters and sort button")
        XCTAssertFalse(play.exists, "The Home billboard should be gone on the Movies tab")

        // 3. Back to Home: the tab bar still holds the focus, one step left.
        remote.press(.left)
        XCTAssertTrue(play.waitForExistence(timeout: 20), "Home should show its billboard again")
    }
}
