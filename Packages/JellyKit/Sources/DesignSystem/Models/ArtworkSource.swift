import Foundation

/// Where an image comes from, plus what to show while it is missing or loading.
public struct ArtworkSource: Sendable, Equatable {
    public let url: URL?
    /// Drives the placeholder: its first letter and a stable hue.
    public let placeholderTitle: String

    public init(url: URL?, placeholderTitle: String) {
        self.url = url
        self.placeholderTitle = placeholderTitle
    }
}
