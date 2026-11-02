import Foundation

/// The `jellyfuse://` links: built by the Top Shelf extension, parsed by the app. One definition for both.
///
/// - `jellyfuse://detail/{id}`: the detail screen of an item.
/// - `jellyfuse://play/{id}?t={seconds}&title={title}`: plays an item, from `t` seconds (absent or 0: the start).
public enum DeepLink: Sendable, Equatable {
    case detail(id: String)
    case play(id: String, title: String, resumeSeconds: Double)

    public static let scheme = "jellyfuse"

    public init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host(percentEncoded: false) else { return nil }
        let id = url.lastPathComponent
        guard !id.isEmpty, id != "/" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        switch host {
        case "detail":
            self = .detail(id: id)
        case "play":
            let seconds = items.first { $0.name == "t" }?.value.flatMap(Double.init) ?? 0
            let title = items.first { $0.name == "title" }?.value ?? ""
            self = .play(id: id, title: title, resumeSeconds: max(0, seconds))
        default:
            return nil
        }
    }

    public var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .detail(let id):
            components.host = "detail"
            components.path = "/" + id
        case .play(let id, let title, let resumeSeconds):
            components.host = "play"
            components.path = "/" + id
            var items = [URLQueryItem(name: "title", value: title)]
            if resumeSeconds > 0 { items.append(URLQueryItem(name: "t", value: String(Int(resumeSeconds)))) }
            components.queryItems = items
        }
        return components.url
    }
}
