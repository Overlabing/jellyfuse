import Foundation
import Testing
@testable import PlayerCore

@Suite struct MpvOptionsTests {
    private func value(_ name: String, in options: MpvOptions) -> String? {
        options.pairs.first { $0.name == name }?.value
    }

    @Test func defaultsMatchValidatedHardwareConfiguration() {
        let options = MpvOptions(shaderCacheDirectory: nil)
        #expect(value("vo", in: options) == "gpu-next")
        #expect(value("gpu-api", in: options) == "vulkan")
        #expect(value("gpu-context", in: options) == "moltenvk")
        #expect(value("hwdec", in: options) == "videotoolbox,videotoolbox-copy")
        #expect(value("keep-open", in: options) == "yes")
        #expect(value("cache", in: options) == "yes")
        #expect(value("demuxer-max-bytes", in: options) == "50MiB")
        #expect(value("demuxer-max-back-bytes", in: options) == "25MiB")
        #expect(value("gpu-shader-cache-dir", in: options) == nil)
    }

    @Test func hwdecFallbackIsConfigurable() {
        let options = MpvOptions(hwdec: ["no"], shaderCacheDirectory: nil)
        #expect(value("hwdec", in: options) == "no")
    }

    @Test func shaderCacheDirectoryIsPassedThrough() {
        let dir = URL(fileURLWithPath: "/tmp/shaders", isDirectory: true)
        #expect(value("gpu-shader-cache-dir", in: MpvOptions(shaderCacheDirectory: dir)) == "/tmp/shaders")
    }

    @Test func metalLayerRejectsDegenerateDrawableSizes() {
        #expect(!MetalLayer.isUsable(CGSize(width: 1, height: 1)))
        #expect(MetalLayer.isUsable(CGSize(width: 3840, height: 2160)))
    }

    @Test func trackKindsMapToMpvProperties() {
        #expect(MpvTrackKind.audio.propertyName == "aid")
        #expect(MpvTrackKind.subtitle.propertyName == "sid")
    }
}
