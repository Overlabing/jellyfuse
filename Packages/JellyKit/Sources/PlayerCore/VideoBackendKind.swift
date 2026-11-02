/// Which video output pipeline mpv uses. Injected through `MpvOptions`; nothing reads it from defaults.
public enum VideoBackendKind: Sendable, Equatable {
    /// `vo=avsamplebuffer` into an AVSampleBufferDisplayLayer. Default: no frame drops on AV1.
    case sampleBuffer
    /// `vo=gpu-next` on MoltenVK into a CAMetalLayer. Explicit opt-in; the HDR fallback.
    case metalLayer

    @MainActor
    func makeSurface() -> any VideoSurfaceBackend {
        switch self {
        case .sampleBuffer: SampleBufferBackend()
        case .metalLayer: MetalLayerBackend()
        }
    }
}
