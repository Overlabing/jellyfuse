import Foundation
import Libmpv

/// Facade over libmpv. The mpv handle never leaves this type: it is created on the main actor,
/// then only touched on a private serial queue. Events come out as `events`.
public final class MpvPlayer: @unchecked Sendable {
    /// Playback events and property changes. Finishes after `shutdown()`.
    public let events: AsyncStream<MpvEvent>
    @MainActor public let surface: any VideoSurfaceBackend

    private let queue = DispatchQueue(label: "dev.antonin.jellytv.mpv", qos: .userInitiated)
    private let continuation: AsyncStream<MpvEvent>.Continuation
    private var handle: OpaquePointer?
    private var wakeup: Unmanaged<WakeupBox>?

    /// Creates and initialises the mpv core, drawing into `surface`.
    @MainActor
    public init(surface: any VideoSurfaceBackend, options: MpvOptions = MpvOptions()) throws {
        guard let handle = mpv_create() else { throw MpvError.creationFailed }
        self.surface = surface
        (events, continuation) = AsyncStream.makeStream(of: MpvEvent.self, bufferingPolicy: .unbounded)
        self.handle = handle

        var wid = surface.renderTarget
        var status = mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &wid)
        for (name, value) in options.pairs {
            let result = mpv_set_option_string(handle, name, value)
            if result < 0 { print("[mpv] option \(name)=\(value) rejected: \(MpvError.describe(result))") }
        }
        if status >= 0 { status = mpv_initialize(handle) }
        guard status >= 0 else {
            mpv_terminate_destroy(handle)
            self.handle = nil
            continuation.finish()
            throw MpvError.initializationFailed(MpvError.describe(status))
        }

        for (name, format) in Self.observed {
            mpv_observe_property(handle, 0, name, format)
        }

        let box = WakeupBox()
        let retained = Unmanaged.passRetained(box)
        wakeup = retained
        box.onWakeup = { [weak self] in self?.drainEvents() }
        mpv_set_wakeup_callback(handle, { context in
            Unmanaged<WakeupBox>.fromOpaque(context!).takeUnretainedValue().onWakeup?()
        }, retained.toOpaque())
    }

    /// Creates the player with the surface matching `options.backend`.
    @MainActor
    public convenience init(options: MpvOptions = MpvOptions()) throws {
        try self.init(surface: options.backend.makeSurface(), options: options)
    }

    deinit { tearDown() }

    // MARK: Commands

    public func loadFile(_ url: URL) {
        command(["loadfile", url.absoluteString, "replace"])
    }

    public func play() { setProperty("pause", "no") }

    public func pause() { setProperty("pause", "yes") }

    public func togglePause() { command(["cycle", "pause"]) }

    /// Absolute seek, in seconds.
    public func seek(to seconds: Double) {
        command(["seek", String(seconds), "absolute"])
    }

    /// Relative seek, in seconds (negative rewinds).
    public func seek(by seconds: Double) {
        command(["seek", String(seconds), "relative"])
    }

    /// Selects a track by mpv id; nil turns the track kind off.
    public func setTrack(_ kind: MpvTrackKind, id: Int?) {
        setProperty(kind.propertyName, id.map(String.init) ?? "no")
    }

    /// Stops playback and destroys the mpv core. Idempotent; `events` finishes.
    public func shutdown() {
        queue.sync { tearDown() }
    }

    /// Runs on `queue`, or in `deinit` where nothing else references the player.
    private func tearDown() {
        guard let handle else { return }
        mpv_set_wakeup_callback(handle, nil, nil)
        mpv_terminate_destroy(handle)
        self.handle = nil
        wakeup?.release()
        wakeup = nil
        continuation.yield(.shutdown)
        continuation.finish()
    }

    // MARK: Internals

    private final class WakeupBox: @unchecked Sendable {
        var onWakeup: (@Sendable () -> Void)?
    }

    private static let observed: [(String, mpv_format)] = [
        ("time-pos", MPV_FORMAT_DOUBLE),
        ("duration", MPV_FORMAT_DOUBLE),
        ("pause", MPV_FORMAT_FLAG),
        ("paused-for-cache", MPV_FORMAT_FLAG),
        ("video-codec", MPV_FORMAT_STRING),
        ("hwdec-current", MPV_FORMAT_STRING),
        ("vo-configured", MPV_FORMAT_FLAG),
    ]

    private func setProperty(_ name: String, _ value: String) {
        queue.async { [self] in
            guard let handle else { return }
            let status = mpv_set_property_string(handle, name, value)
            if status < 0 { print("[mpv] set \(name)=\(value) failed: \(MpvError.describe(status))") }
        }
    }

    private func command(_ args: [String]) {
        queue.async { [self] in
            guard let handle else { return }
            var cargs: [UnsafePointer<CChar>?] = args.map { UnsafePointer(strdup($0)) } + [nil]
            defer { for pointer in cargs { free(UnsafeMutablePointer(mutating: pointer)) } }
            let status = mpv_command(handle, &cargs)
            if status < 0 { print("[mpv] \(args.first ?? "?") failed: \(MpvError.describe(status))") }
        }
    }

    private func drainEvents() {
        queue.async { [self] in
            while let handle {
                guard let event = mpv_wait_event(handle, 0), event.pointee.event_id != MPV_EVENT_NONE else { return }
                if let mapped = Self.map(event.pointee) { continuation.yield(mapped) }
            }
        }
    }

    private static func map(_ event: mpv_event) -> MpvEvent? {
        switch event.event_id {
        case MPV_EVENT_START_FILE:
            return .startFile
        case MPV_EVENT_FILE_LOADED:
            return .fileLoaded
        case MPV_EVENT_END_FILE:
            guard let end = UnsafePointer<mpv_event_end_file>(OpaquePointer(event.data))?.pointee else { return nil }
            return .endFile(error: end.reason == MPV_END_FILE_REASON_ERROR ? MpvError.describe(end.error) : nil)
        case MPV_EVENT_PROPERTY_CHANGE:
            guard let property = UnsafePointer<mpv_event_property>(OpaquePointer(event.data))?.pointee,
                  let mapped = mapProperty(property) else { return nil }
            return .propertyChanged(mapped)
        default:
            return nil
        }
    }

    private static func mapProperty(_ property: mpv_event_property) -> MpvProperty? {
        guard let data = property.data else { return nil }
        let name = String(cString: property.name)
        switch (name, property.format) {
        case ("time-pos", MPV_FORMAT_DOUBLE): return .timePosition(data.load(as: Double.self))
        case ("duration", MPV_FORMAT_DOUBLE): return .duration(data.load(as: Double.self))
        case ("pause", MPV_FORMAT_FLAG): return .paused(data.load(as: Int32.self) > 0)
        case ("paused-for-cache", MPV_FORMAT_FLAG): return .pausedForCache(data.load(as: Int32.self) > 0)
        case ("vo-configured", MPV_FORMAT_FLAG): return .videoConfigured(data.load(as: Int32.self) > 0)
        case ("video-codec", MPV_FORMAT_STRING): return .videoCodec(string(data))
        case ("hwdec-current", MPV_FORMAT_STRING): return .hwdecCurrent(string(data))
        default: return nil
        }
    }

    private static func string(_ data: UnsafeMutableRawPointer) -> String {
        data.load(as: UnsafePointer<CChar>?.self).map { String(cString: $0) } ?? ""
    }
}

public enum MpvError: Error, Equatable {
    case creationFailed
    case initializationFailed(String)

    static func describe(_ status: CInt) -> String {
        String(cString: mpv_error_string(status))
    }
}
