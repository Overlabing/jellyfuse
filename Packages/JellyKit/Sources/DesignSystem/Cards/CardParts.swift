import SwiftUI

/// Title and subtitle under a card (outside the focusable artwork, like the Apple TV app).
struct CardCaption: View {
    let title: String
    let subtitle: String?
    let width: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text(title)
                .font(Design.Typography.body.weight(.semibold))
                .foregroundStyle(Design.Palette.textPrimary)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

/// Artwork with rounded corners, optional progress bar, brightened when focused.
struct CardArtwork<Overlay: View>: View {
    let source: ArtworkSource
    let size: CGSize
    let progress: Double?
    @ViewBuilder let overlay: Overlay
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Artwork(source)
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .bottom) {
                if let progress { ProgressBar(progress: progress) }
            }
            .overlay(alignment: .topTrailing) { overlay }
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card))
            .brightness(isFocused ? Design.Focus.imageBrightness : 0)
    }
}

/// Green check shown on watched posters.
struct WatchedFlag: View {
    @Environment(\.designMetrics) private var metrics
    var body: some View {
        Image(systemName: "checkmark")
            .font(Design.Typography.callout.weight(.heavy))
            .foregroundStyle(Design.Palette.success)
            .frame(width: metrics.watchedFlag, height: metrics.watchedFlag)
            .background(.black.opacity(0.55), in: Circle())
            .padding(Design.Spacing.s)
    }
}
