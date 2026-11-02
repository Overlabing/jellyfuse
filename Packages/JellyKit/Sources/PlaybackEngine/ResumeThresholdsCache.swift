import Foundation

/// The server's resume thresholds, fetched lazily and kept once read. A failed fetch is not cached:
/// the next call retries, so a stop made offline still gets its local patch if an earlier call succeeded.
public actor ResumeThresholdsCache {
    private let fetch: @Sendable () async throws -> ResumeThresholds?
    private var cached: ResumeThresholds?

    public init(fetch: @escaping @Sendable () async throws -> ResumeThresholds?) {
        self.fetch = fetch
    }

    public func value() async -> ResumeThresholds? {
        if let cached { return cached }
        cached = try? await fetch()
        return cached
    }
}
