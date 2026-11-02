import SwiftUI

/// 2:3 poster card. Focus is the system borderless effect (lift, shadow, parallax) plus a slight brightness boost.
public struct PosterCard: View {
    @Environment(\.designMetrics) private var metrics
    @FocusState private var isFocused: Bool
    private let model: PosterModel
    private let onSelect: () -> Void

    public init(_ model: PosterModel, onSelect: @escaping () -> Void) {
        self.model = model
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.s) {
            Button(action: onSelect) {
                    CardArtwork(source: model.image, size: metrics.poster, progress: model.progress) {
                    if model.isWatched { WatchedFlag() }
                }
            }
            .cardButtonStyle()
            .focused($isFocused)
            CardCaption(
                title: model.title, subtitle: model.subtitle, width: metrics.poster.width,
                isFocused: isFocused, focusShift: metrics.poster.height * (Design.Focus.scale - 1) / 2
            )
        }
        .accessibilityLabel(model.accessibilityDescription)
    }
}

#if DEBUG
#Preview("PosterCard – normal / focus / progress / watched") {
    PreviewFocusScope { namespace in
        HStack(alignment: .top, spacing: Design.Metrics.tv.shelfGap) {
            PosterCard(PreviewData.posters[0]) {}
            PosterCard(PreviewData.posters[1]) {}.previewDefaultFocus(in: namespace)
            PosterCard(PreviewData.posters[2]) {}
            PosterCard(PreviewData.posters[3]) {}
        }
    }
}
#endif
