import SwiftUI

/// Gradient + initial shown when an image is missing or loading (mockup `.art`).
struct PlaceholderArtwork: View {
    let title: String

    var body: some View {
        let hue = PlaceholderStyle.hue(for: title)
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                LinearGradient(
                    colors: [
                        color(hue: hue, saturation: Design.Placeholder.saturationTop, lightness: Design.Placeholder.lightnessTop),
                        color(
                            hue: hue + Design.Placeholder.hueSpread,
                            saturation: Design.Placeholder.saturationBottom,
                            lightness: Design.Placeholder.lightnessBottom
                        ),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [.white.opacity(Design.Placeholder.highlightOpacity), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: proxy.size.width * 0.7
                )
                Text(PlaceholderStyle.initial(for: title))
                    .font(.system(size: side * Design.Placeholder.initialScale, weight: .black))
                    .foregroundStyle(.white.opacity(Design.Placeholder.initialOpacity))
                    .offset(
                        x: proxy.size.width * Design.Placeholder.initialOffsetX,
                        y: proxy.size.height * Design.Placeholder.initialOffsetY
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                LinearGradient(
                    colors: [.clear, .black.opacity(Design.Placeholder.bottomShadeOpacity)],
                    startPoint: UnitPoint(x: 0.5, y: 0.45),
                    endPoint: .bottom
                )
            }
            .clipped()
        }
        .accessibilityHidden(true)
    }

    private func color(hue: Double, saturation: Double, lightness: Double) -> Color {
        let rgb = PlaceholderStyle.rgb(hue: hue, saturation: saturation, lightness: lightness)
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}

/// Remote image over its placeholder. Fills the space it is given; the caller sets the frame.
public struct Artwork: View {
    private let source: ArtworkSource

    public init(_ source: ArtworkSource) {
        self.source = source
    }

    public var body: some View {
        // The placeholder dictates the size (it fills the proposal); the image is an overlay so a
        // scaledToFill image can never inflate the layout size of the view.
        PlaceholderArtwork(title: source.placeholderTitle)
            .overlay {
                if let url = source.url {
                    RemoteImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill().transition(.opacity)
                        }
                    }
                }
            }
        .clipped()
    }
}

#if DEBUG
#Preview("Artwork placeholders") {
    HStack(spacing: Design.Metrics.tv.shelfGap) {
        ForEach(PreviewData.titles, id: \.self) { title in
            Artwork(ArtworkSource(url: nil, placeholderTitle: title))
                .frame(width: Design.Metrics.tv.poster.width, height: Design.Metrics.tv.poster.height)
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card))
        }
    }
    .padding(Design.Metrics.tv.screenMargin)
    .background(Design.Palette.canvas)
}
#endif
