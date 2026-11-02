import Foundation

/// mpv configuration. Defaults are the values validated on Apple TV hardware (Phase 0).
public struct MpvOptions: Sendable, Equatable {
    /// Video output pipeline. `.sampleBuffer` carries the production recipe (decode queue, AVFoundation audio).
    public var backend: VideoBackendKind
    /// Hardware decoders in priority order. mpv tries each in turn, so the zero-copy
    /// `videotoolbox` falls back to `videotoolbox-copy` by itself. Use `["no"]` to force software.
    public var hwdec: [String]
    public var demuxerMaxBytes: String
    public var demuxerMaxBackBytes: String
    /// mpv `msg-level` value, e.g. `all=warn` or `all=v`.
    public var messageLevel: String
    /// Persistent shader/pipeline cache directory; nil disables it.
    public var shaderCacheDirectory: URL?

    public init(
        backend: VideoBackendKind = .sampleBuffer,
        hwdec: [String] = ["videotoolbox", "videotoolbox-copy"],
        demuxerMaxBytes: String = "50MiB",
        demuxerMaxBackBytes: String = "25MiB",
        messageLevel: String = "all=warn",
        shaderCacheDirectory: URL? = MpvOptions.defaultShaderCacheDirectory
    ) {
        self.backend = backend
        self.hwdec = hwdec
        self.demuxerMaxBytes = demuxerMaxBytes
        self.demuxerMaxBackBytes = demuxerMaxBackBytes
        self.messageLevel = messageLevel
        self.shaderCacheDirectory = shaderCacheDirectory
    }

    public static var defaultShaderCacheDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("mpv-shader-cache", isDirectory: true)
    }

    /// The `name=value` pairs set before `mpv_initialize`, in order.
    var pairs: [(name: String, value: String)] {
        var out: [(String, String)] = [
            // terminal input/stdout belongs to CLI mpv; with stdin closed (home-screen
            // launch) mpv reads EOF and quits the process.
            ("terminal", "no"),
            ("msg-level", messageLevel),
            ("hwdec", hwdec.joined(separator: ",")),
            ("keep-open", "yes"),
            ("cache", "yes"),
            ("demuxer-max-bytes", demuxerMaxBytes),
            ("demuxer-max-back-bytes", demuxerMaxBackBytes),
            ("video-rotate", "no"),
            ("subs-match-os-language", "yes"),
            ("subs-fallback", "yes"),
        ]
        switch backend {
        case .sampleBuffer:
            out += [
                ("vo", "avsamplebuffer"),
                ("vd-queue-enable", "yes"),
                ("vd-queue-max-secs", "2"),
                ("ao", "avfoundation"),
                ("audio-channels", "stereo"),
            ]
        case .metalLayer:
            out += [
                ("vo", "gpu-next"),
                ("gpu-api", "vulkan"),
                ("gpu-context", "moltenvk"),
            ]
            if let dir = shaderCacheDirectory {
                out.append(("gpu-shader-cache-dir", dir.path))
            }
        }
        return out
    }
}
