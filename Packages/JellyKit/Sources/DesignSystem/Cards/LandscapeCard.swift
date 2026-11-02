import SwiftUI

/// 16:9 card for continue watching, next up and episodes, with a progress bar.
public struct LandscapeCard: View {
    @Environment(\.designMetrics) private var metrics
    private let model: LandscapeModel
    private let onSelect: () -> Void

    public init(_ model: LandscapeModel, onSelect: @escaping () -> Void) {
        self.model = model
        self.onSelect = onSelect
    }

    public var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Design.Spacing.s) {
                CardArtwork(source: model.image, size: metrics.landscape, progress: model.progress) {
                    EmptyView()
                }
                CardCaption(title: model.title, subtitle: model.subtitle, width: metrics.landscape.width)
            }
        }
        .cardButtonStyle()
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
