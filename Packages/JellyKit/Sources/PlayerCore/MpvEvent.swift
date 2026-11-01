/// A property whose changes are observed.
public enum MpvProperty: Sendable, Equatable {
    case timePosition(Double)
    case duration(Double)
    case paused(Bool)
    case pausedForCache(Bool)
    case videoCodec(String)
    case hwdecCurrent(String)
    case videoConfigured(Bool)
}

public enum MpvTrackKind: Sendable {
    case audio, subtitle

    var propertyName: String {
        switch self {
        case .audio: "aid"
        case .subtitle: "sid"
        }
    }
}

public enum MpvEvent: Sendable, Equatable {
    case startFile
    case fileLoaded
    /// `error` is nil for a normal end (EOF, stop).
    case endFile(error: String?)
    case propertyChanged(MpvProperty)
    case shutdown
}
