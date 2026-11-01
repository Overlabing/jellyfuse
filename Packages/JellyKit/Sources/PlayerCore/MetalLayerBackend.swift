import UIKit

/// `VideoSurfaceBackend` drawing into a CAMetalLayer (`gpu-context=moltenvk`).
@MainActor
public final class MetalLayerBackend: VideoSurfaceBackend {
    private let layer = MetalLayer()

    public init() {
        layer.contentsScale = UIScreen.main.nativeScale
        layer.framebufferOnly = true
        layer.backgroundColor = UIColor.black.cgColor
    }

    public var renderTarget: Int64 {
        Int64(UInt(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
    }

    public func install(in view: UIView) {
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
    }

    public func layoutSurface(in bounds: CGRect) {
        layer.frame = bounds
    }
}
