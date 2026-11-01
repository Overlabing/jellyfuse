import UIKit

/// Workaround for MoltenVK setting drawableSize to 1x1 (https://github.com/mpv-player/mpv/pull/13651).
final class MetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if Self.isUsable(newValue) { super.drawableSize = newValue }
        }
    }

    static func isUsable(_ size: CGSize) -> Bool {
        Int(size.width) > 1 && Int(size.height) > 1
    }
}
