import Foundation

/// When the home screen revalidates by itself. `HomeModel.refresh()` only reloads stale shelves, so a
/// tick on fresh data costs no request.
public enum HomeRefreshPolicy {
    public static let pollInterval: Duration = .seconds(120)

    /// Poll only while the user can see the home: app in the foreground, home on screen, no player over it.
    public static func shouldPoll(sceneIsActive: Bool, homeIsVisible: Bool, playerIsOpen: Bool) -> Bool {
        sceneIsActive && homeIsVisible && !playerIsOpen
    }
}
