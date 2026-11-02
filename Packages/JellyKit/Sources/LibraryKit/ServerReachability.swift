import Foundation
import Network
import Observation

/// Whether the device has a network and whether the Jellyfin server answers on it.
///
/// `NWPathMonitor` says if any network is up at all; it cannot see a VPN that is down, so the server
/// is also probed (through the SDK, see `JellyfinClient.ping`) and any network failure reported by a
/// client marks it unreachable until a probe or a success says otherwise.
@MainActor
@Observable
public final class ServerReachability {
    public enum Connectivity: Sendable, Equatable {
        case online
        /// No network path at all (no Wi-Fi, no ethernet).
        case offline
        /// A network exists but the server does not answer (VPN down, server off, wrong address).
        case serverUnreachable
    }

    public private(set) var connectivity: Connectivity = .online
    /// Called on the main actor each time `connectivity` changes, with the previous value.
    @ObservationIgnored public var onChange: (@MainActor (Connectivity) -> Void)?

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var hasPath = true
    @ObservationIgnored private var probeTask: Task<Void, Never>?
    @ObservationIgnored private let probe: @Sendable () async -> Bool

    public var isOnline: Bool { connectivity == .online }

    /// `probe` answers whether the server responds, e.g. `{ await client.ping() }`.
    public init(probe: @escaping @Sendable () async -> Bool) {
        self.probe = probe
        // The handler runs on the monitor's queue: it must not inherit this actor's isolation.
        monitor.pathUpdateHandler = Self.makePathHandler(self)
        monitor.start(queue: DispatchQueue(label: "jellyfuse.reachability", qos: .utility))
    }

    deinit { monitor.cancel() }

    private nonisolated static func makePathHandler(_ owner: ServerReachability) -> @Sendable (NWPath) -> Void {
        { @Sendable [weak owner] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in owner?.pathChanged(satisfied: satisfied) }
        }
    }

    func pathChanged(satisfied: Bool) {
        hasPath = satisfied
        if !satisfied { set(.offline) } else if connectivity == .offline { set(.online) }
    }

    /// A client got a network error: the server is unreachable (or there is no network).
    public func reportFailure(_ error: any Error) {
        guard UserFacingError.isNetwork(error) else { return }
        set(hasPath ? .serverUnreachable : .offline)
    }

    /// A client got an answer from the server.
    public func reportSuccess() {
        set(.online)
    }

    /// Asks the server directly, then updates `connectivity`. Concurrent calls share one probe.
    public func check() async {
        if let probeTask { await probeTask.value; return }
        let task = Task { [probe] in
            let reachable = await probe()
            self.set(reachable ? .online : (self.hasPath ? .serverUnreachable : .offline))
        }
        probeTask = task
        await task.value
        probeTask = nil
    }

    private func set(_ value: Connectivity) {
        guard value != connectivity else { return }
        let previous = connectivity
        connectivity = value
        onChange?(previous)
    }
}
