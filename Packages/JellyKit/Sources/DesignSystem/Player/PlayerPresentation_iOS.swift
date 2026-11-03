#if os(iOS)
import SwiftUI
import UIKit

/// The orientations the app currently allows. SwiftUI has no orientation lock of its own: the app's delegate
/// returns `PlayerOrientationLock.mask` from
/// `application(_:supportedInterfaceOrientationsFor:)`, and `playerFullScreen()` flips it while the player is up.
@MainActor
public enum PlayerOrientationLock {
    /// What the app allows outside the player (phones: portrait + landscape; iPads: all).
    public static var base: UIInterfaceOrientationMask = UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    public static var mask: UIInterfaceOrientationMask = base

    /// Landscape only, and rotates the interface there if it is not already.
    static func lockLandscape() {
        mask = .landscape
        requestGeometry(.landscape)
    }

    /// Back to what the rest of the app allows.
    static func unlock() {
        mask = base
        requestGeometry(base)
    }

    private static func requestGeometry(_ orientations: UIInterfaceOrientationMask) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        scene?.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene?.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { _ in }
    }
}

extension View {
    /// The player's screen presentation: status bar and home indicator hidden, content edge to edge, landscape
    /// preferred (locked while the player is on screen, released on exit). Apply it to the player's root view.
    public func playerFullScreen() -> some View {
        statusBarHidden()
            .persistentSystemOverlays(.hidden)
            .ignoresSafeArea()
            .onAppear { PlayerOrientationLock.lockLandscape() }
            .onDisappear { PlayerOrientationLock.unlock() }
    }
}
#endif
