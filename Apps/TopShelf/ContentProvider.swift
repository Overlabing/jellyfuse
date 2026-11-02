import Foundation
import LibraryKit
import TVServices

/// The Top Shelf: the row above the dock when Jellyfuse is on the first line shows « À suivre » (resume,
/// then next up) as a sectioned row of 16:9 cards. Sectioned rather than carousel: a carousel wants
/// full-bleed 1920x720 artwork (backdrops cropped for it), whereas the cards fit Thumb/Backdrop/episode
/// stills as they are and stay readable with several items.
///
/// Read-only: the session comes from the keychain group the app writes, and two light requests fetch the
/// items. Without a session (or on any failure) the content is nil and the system keeps the static brand image.
final class ContentProvider: TVTopShelfContentProvider {
    private static let limit = 10
    private static let imageWidth = 640

    override func loadTopShelfContent(completionHandler: @escaping ((any TVTopShelfContent)?) -> Void) {
        // The async override trips Swift 6 Sendable checks on the content object: the callback form keeps
        // the content built and handed over inside one task.
        nonisolated(unsafe) let done = completionHandler
        Task {
            SessionStore.accessGroup = "39TMVBW2CY.com.jellyfusion.app.shared"
            guard let session = SessionStore.load(),
                  let items = try? await Self.upNext(session: session), !items.isEmpty
            else { return done(nil) }
            let section = TVTopShelfItemCollection(items: items.map(Self.card(for:)))
            section.title = "À suivre"
            done(TVTopShelfSectionedContent(sections: [section]))
        }
    }

    // MARK: Cards

    private static func card(for item: UpNextItem) -> TVTopShelfSectionedItem {
        let card = TVTopShelfSectionedItem(identifier: item.id)
        card.title = item.title
        card.imageShape = .hdtv
        if let url = item.imageURL { card.setImageURL(url, for: .screenScale1x) }
        if let progress = item.progress { card.playbackProgress = progress }
        // Select opens the detail screen (the series for an episode); play/pause plays at once.
        card.displayAction = DeepLink.detail(id: item.detailId).url.map { TVTopShelfAction(url: $0) }
        card.playAction = DeepLink.play(id: item.id, title: item.title, resumeSeconds: item.resumeSeconds).url.map { TVTopShelfAction(url: $0) }
        return card
    }

    // MARK: Network

    private static func upNext(session: Session) async throws -> [UpNextItem] {
        async let resume = fetch(session: session, path: "/Users/\(session.userId)/Items/Resume",
                                 extra: [URLQueryItem(name: "MediaTypes", value: "Video")])
        async let next = fetch(session: session, path: "/Shows/NextUp",
                               extra: [URLQueryItem(name: "UserId", value: session.userId)])
        var seen = Set<String>()
        let merged = try await resume + ((try? await next) ?? [])
        return Array(merged.filter { seen.insert($0.id).inserted }.prefix(limit))
    }

    private static func fetch(session: Session, path: String, extra: [URLQueryItem]) async throws -> [UpNextItem] {
        var components = URLComponents(url: session.serverURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = extra + [
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: "ParentBackdropItemId,ParentBackdropImageTags"),
            URLQueryItem(name: "EnableImageTypes", value: "Thumb,Backdrop,Primary"),
        ]
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(
            "MediaBrowser Client=\"Jellyfuse\", Device=\"Apple TV\", DeviceId=\"\(session.deviceId)\", Version=\"0.1.0\", Token=\"\(session.token)\"",
            forHTTPHeaderField: "Authorization"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Page.self, from: data).items.map { UpNextItem(dto: $0, serverURL: session.serverURL) }
    }

    private struct Page: Decodable {
        let items: [Dto]
        enum CodingKeys: String, CodingKey { case items = "Items" }
    }

    struct Dto: Decodable {
        let id: String
        let name: String?
        let seriesName: String?
        let seriesId: String?
        let indexNumber: Int?
        let parentIndexNumber: Int?
        let imageTags: [String: String]?
        let backdropImageTags: [String]?
        let parentBackdropItemId: String?
        let parentBackdropImageTags: [String]?
        let runTimeTicks: Int64?
        let userData: UserDataDto?

        struct UserDataDto: Decodable {
            let playbackPositionTicks: Int64?
            enum CodingKeys: String, CodingKey { case playbackPositionTicks = "PlaybackPositionTicks" }
        }

        enum CodingKeys: String, CodingKey {
            case id = "Id", name = "Name", seriesName = "SeriesName", seriesId = "SeriesId"
            case indexNumber = "IndexNumber", parentIndexNumber = "ParentIndexNumber"
            case imageTags = "ImageTags", backdropImageTags = "BackdropImageTags"
            case parentBackdropItemId = "ParentBackdropItemId", parentBackdropImageTags = "ParentBackdropImageTags"
            case runTimeTicks = "RunTimeTicks", userData = "UserData"
        }
    }

    struct UpNextItem {
        let id: String
        let title: String
        let detailId: String
        let imageURL: URL?
        let resumeSeconds: Double
        let progress: Double?

        init(dto: Dto, serverURL: URL) {
            id = dto.id
            detailId = dto.seriesId ?? dto.id
            let episode = dto.seriesName != nil
            if let series = dto.seriesName, let number = dto.indexNumber {
                let season = dto.parentIndexNumber.map { "S\($0) " } ?? ""
                title = "\(series) · \(season)E\(number)"
            } else {
                title = (episode ? dto.seriesName : dto.name) ?? dto.name ?? ""
            }
            let ticks = dto.userData?.playbackPositionTicks ?? 0
            resumeSeconds = Double(ticks) / 10_000_000
            progress = ticks > 0 ? dto.runTimeTicks.map { Double(ticks) / Double($0) } : nil

            // Wide artwork first (Thumb, then Backdrop, then the series' own), the episode still last.
            let candidates: [(String, String, String?)] = [
                (dto.id, "Thumb", dto.imageTags?["Thumb"]),
                (dto.id, "Backdrop", dto.backdropImageTags?.first),
                (dto.parentBackdropItemId ?? dto.id, "Backdrop", dto.parentBackdropImageTags?.first),
                (dto.id, "Primary", dto.imageTags?["Primary"]),
            ]
            imageURL = candidates.lazy.compactMap { id, kind, tag -> URL? in
                guard let tag else { return nil }
                var components = URLComponents(url: serverURL.appending(path: "/Items/\(id)/Images/\(kind)"), resolvingAgainstBaseURL: false)
                components?.queryItems = [
                    URLQueryItem(name: "maxWidth", value: String(ContentProvider.imageWidth)),
                    URLQueryItem(name: "quality", value: "90"),
                    URLQueryItem(name: "tag", value: tag),
                ]
                return components?.url
            }.first
        }
    }
}
