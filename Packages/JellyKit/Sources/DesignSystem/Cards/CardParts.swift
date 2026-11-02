import SwiftUI

/// Title and subtitle under a card (outside the focusable artwork, like the Apple TV app).
/// Focused, the caption slides down as if pushed by the growing artwork, and the title lights up
/// from the subtitle's gray to white.
struct CardCaption: View {
    let title: String
    let subtitle: String?
    let width: CGFloat
    var isFocused = false
    /// How far the growing artwork pushes the caption down: half the artwork's extra height.
    var focusShift: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text(title)
                .font(Design.Typography.body.weight(.semibold))
                .foregroundStyle(isFocused ? Design.Palette.textPrimary : Design.Palette.textSecondary)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: width, alignment: .leading)
        .offset(y: isFocused ? focusShift : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isFocused)
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
