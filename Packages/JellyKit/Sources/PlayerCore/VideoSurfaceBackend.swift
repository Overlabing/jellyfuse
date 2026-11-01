import UIKit

/// Where mpv draws. The seam between the player and the platform surface: the tvOS
/// implementation is a CAMetalLayer; a PiP-capable iOS backend plugs in here later.
@MainActor
public protocol VideoSurfaceBackend: AnyObject {
    /// Value for mpv's `wid` option: the address of the native render target.
    var renderTarget: Int64 { get }
    /// Adds the surface to the view hierarchy.
    func install(in view: UIView)
    /// Called whenever the hosting view's bounds change.
    func layoutSurface(in bounds: CGRect)
}
