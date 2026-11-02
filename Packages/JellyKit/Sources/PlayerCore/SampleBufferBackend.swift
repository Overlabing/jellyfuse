import AVFoundation
import UIKit

/// `VideoSurfaceBackend` presenting decoded frames through an AVSampleBufferDisplayLayer
/// (`vo=avsamplebuffer`, the custom libmpv video output). No GPU API or context is involved.
@MainActor
public final class SampleBufferBackend: VideoSurfaceBackend {
    private let layer = AVSampleBufferDisplayLayer()

    public init() {
        layer.videoGravity = .resizeAspect
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
