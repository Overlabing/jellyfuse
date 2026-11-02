import SwiftUI
#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

/// In-memory cache of decoded artwork. `AsyncImage` has none: every shelf cell that scrolls back into view
/// would show its placeholder again and re-download (tvOS keeps no useful URL disk cache). Decoded once
/// (`byPreparingForDisplay`, off the main thread) so scrolling never pays for decoding either.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let storage = NSCache<NSURL, PlatformImage>()

    init(costLimit: Int = 160 * 1024 * 1024) {
        storage.totalCostLimit = costLimit
    }

    func cached(_ url: URL) -> PlatformImage? { storage.object(forKey: url as NSURL) }

    /// The image at `url`: from memory, else downloaded and decoded. Throws on network failure or undecodable data.
    func image(for url: URL) async throws -> PlatformImage {
        if let hit = cached(url) { return hit }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw URLError(.badServerResponse) }
        guard let decoded = PlatformImage(data: data) else { throw URLError(.cannotDecodeContentData) }
        #if canImport(UIKit)
        let image = await decoded.byPreparingForDisplay() ?? decoded
        let pixels = Int(image.size.width * image.scale * image.size.height * image.scale) * 4
        #else
        let image = decoded
        let pixels = data.count * 4
        #endif
        storage.setObject(image, forKey: url as NSURL, cost: pixels)
        return image
    }
}

enum RemoteImagePhase {
    case loading
    case success(Image)
    case failure
}

/// `AsyncImage` with a memory cache: a URL already seen renders on the first frame, with no placeholder flash.
struct RemoteImage<Content: View>: View {
    private let url: URL
    private let content: (RemoteImagePhase) -> Content
    @State private var phase: RemoteImagePhase

    init(url: URL, @ViewBuilder content: @escaping (RemoteImagePhase) -> Content) {
        self.url = url
        self.content = content
        _phase = State(initialValue: ImageCache.shared.cached(url).map { .success(Image(platformImage: $0)) } ?? .loading)
    }

    var body: some View {
        // The caller's closure may render nothing for a phase (Artwork shows only success). A view that
        // renders nothing never appears, so a task attached to it never runs: the ZStack is the always-
        // present node that owns the download task.
        ZStack { content(phase) }
            .task(id: url) {
                if let hit = ImageCache.shared.cached(url) {
                    phase = .success(Image(platformImage: hit))
                    return
                }
                phase = .loading
                do {
                    phase = .success(Image(platformImage: try await ImageCache.shared.image(for: url)))
                } catch is CancellationError {
                    // Scrolled away: nothing to show, nothing to cache.
                } catch {
                    #if DEBUG
                    print("RemoteImage FAILED \(url.lastPathComponent): \(error)")
                    #endif
                    phase = .failure
                }
            }
    }
}
