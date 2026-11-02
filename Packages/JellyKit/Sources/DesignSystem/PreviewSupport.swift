#if DEBUG
import SwiftUI

extension View {
    /// Preview-only, tvOS/macOS focus engine: no-op where `prefersDefaultFocus` does not exist.
    func previewDefaultFocus(_ prefers: Bool = true, in namespace: Namespace.ID) -> some View {
        #if os(tvOS) || os(macOS)
        prefersDefaultFocus(prefers, in: namespace)
        #else
        self
        #endif
    }

    func previewFocusScope(_ namespace: Namespace.ID) -> some View {
        #if os(tvOS) || os(macOS)
        focusScope(namespace)
        #else
        self
        #endif
    }
}

/// Preview-only: canvas background and a focus scope, so one view can be defaulted to focused.
struct PreviewFocusScope<Content: View>: View {
    @Namespace private var namespace
    let content: (Namespace.ID) -> Content

    init(@ViewBuilder content: @escaping (Namespace.ID) -> Content) {
        self.content = content
    }

    var body: some View {
        content(namespace)
            .previewFocusScope(namespace)
            .padding(.horizontal, Design.Metrics.tv.screenMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Design.Palette.canvas)
    }
}

enum PreviewData {
    static let titles = ["Nocturne", "La Dernière Marée", "Fréquences", "Atlas"]

    private static func art(_ title: String) -> ArtworkSource {
        ArtworkSource(url: nil, placeholderTitle: title)
    }

    static let posters: [PosterModel] = [
        PosterModel(id: "p1", title: "Nocturne", subtitle: "2025", image: art("Nocturne")),
        PosterModel(id: "p2", title: "La Dernière Marée", subtitle: "2024", image: art("La Dernière Marée"), progress: 0.18),
        PosterModel(id: "p3", title: "Fréquences", subtitle: "2023", image: art("Fréquences"), isWatched: true),
        PosterModel(id: "p4", title: "Atlas", subtitle: "2022", image: art("Atlas")),
        PosterModel(id: "p5", title: "Brume", subtitle: "2021", image: art("Brume")),
        PosterModel(id: "p6", title: "Cendres", subtitle: "2020", image: art("Cendres")),
        PosterModel(id: "p7", title: "Dérive", subtitle: "2019", image: art("Dérive")),
    ]

    static let landscapes: [LandscapeModel] = [
        LandscapeModel(id: "l1", title: "Nocturne", subtitle: "S1 E3 · 28 min restantes", image: art("Nocturne"), progress: 0.62),
        LandscapeModel(id: "l2", title: "La Dernière Marée", subtitle: "1 h 12 restantes", image: art("La Dernière Marée"), progress: 0.18),
        LandscapeModel(id: "l3", title: "Fréquences", subtitle: "S2 E5 · 41 min restantes", image: art("Fréquences"), progress: 0.74),
        LandscapeModel(id: "l4", title: "Atlas", subtitle: "S1 E1", image: art("Atlas")),
    ]

    static let people: [PersonModel] = [
        PersonModel(id: "c1", name: "Inès Marchand", role: "Léa", image: art("Inès Marchand")),
        PersonModel(id: "c2", name: "Tom Duval", role: "Samuel", image: art("Tom Duval")),
        PersonModel(id: "c3", name: "Salomé Ricard", role: "Réalisation", image: art("Salomé Ricard")),
    ]

    static let detailHeader = DetailHeaderModel(
        id: "d1",
        title: "Fréquences",
        backdrop: art("Fréquences"),
        overview: "Un signal impossible, venu d'une station arrêtée depuis quarante ans.",
        rating: 8.4,
        certification: "12",
        yearText: "2022 – 2025",
        seasonCount: 4,
        genres: ["Science-fiction", "Mystère"]
    )

    static let billboard = BillboardModel(
        id: "b1",
        title: "Nocturne",
        overview: "Une nuit, une ville sans électricité et un secret que personne ne devait retrouver. Une enquêtrice reprend un dossier classé, et chaque indice la ramène à la même rue.",
        backdrop: art("Nocturne"),
        rating: 7.8,
        year: 2025,
        runtimeMinutes: 128
    )
}
#endif
