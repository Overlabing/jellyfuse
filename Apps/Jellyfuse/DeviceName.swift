import UIKit

/// How Jellyfin lists this client in its dashboard and sessions: « iPhone », « iPad » or « Apple TV ».
@MainActor
enum DeviceName {
    static var current: String { UIDevice.current.model }
}
