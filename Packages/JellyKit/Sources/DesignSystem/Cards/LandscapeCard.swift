import SwiftUI

/// 16:9 card for continue watching, next up and episodes, with a progress bar.
public struct LandscapeCard: View {
    @Environment(\.designMetrics) private var metrics
    private let model: LandscapeModel
    private let onSelect: () -> Void
    private let onToggleWatched: (() -> Void)?

    /// `onToggleWatched` adds the long-press menu « Marquer comme vu » / « Marquer non vu ».
    public init(_ model: LandscapeModel, onToggleWatched: (() -> Void)? = nil, onSelect: @escaping () -> Void) {
        self.model = model
        self.onToggleWatched = onToggleWatched
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.s) {
            Button(action: onSelect) {
                CardArtwork(source: model.image, size: metrics.landscape, progress: model.progress) {
                    if model.isWatched { WatchedFlag() }
                }
            }
            .cardButtonStyle()
            .contextMenu {
                if let onToggleWatched {
                    Button(
                        model.isWatched ? String(localized: "Marquer non vu") : String(localized: "Marquer comme vu"),
                        systemImage: model.isWatched ? "eye.slash" : "eye",
                        action: onToggleWatched
                    )
                }
            }
            CardCaption(title: model.title, subtitle: model.subtitle, width: metrics.landscape.width)
        }
        .accessibilityLabel(model.accessibilityDescription)
    }
}

#if DEBUG
#Preview("LandscapeCard – normal / focus") {
    PreviewFocusScope { namespace in
        HStack(alignment: .top, spacing: Design.Metrics.tv.shelfGap) {
            LandscapeCard(PreviewData.landscapes[0]) {}
            LandscapeCard(PreviewData.landscapes[1]) {}.previewDefaultFocus(in: namespace)
            LandscapeCard(PreviewData.landscapes[2]) {}
        }
    }
}
#endif
