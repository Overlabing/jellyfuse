import SwiftUI

/// Platform-neutral design tokens for Jellyfuse (palette, scale, radius, semantic text styles).
/// Layout metrics (margins, card sizes) are NOT here: see `Design.Metrics`. Source of truth: `docs/design/ui-plan.md` §3 and the HTML mockups.
/// No raw number or color literal may appear in a view: go through this namespace.
public enum Design {
    // MARK: Palette

    public enum Palette {
        public static let canvasHex: UInt32 = 0x07070B
        public static let surfaceHex: UInt32 = 0x101018
        public static let textPrimaryHex: UInt32 = 0xF4F4F8
        public static let textSecondaryHex: UInt32 = 0xA6A6B8
        public static let textTertiaryHex: UInt32 = 0x6E6E82
        public static let accentHex: UInt32 = 0x8A6CFF
        public static let gradientMidHex: UInt32 = 0xC65BDB
        public static let sparkHex: UInt32 = 0xFF5C8A
        public static let successHex: UInt32 = 0x3DDC97
        public static let warningHex: UInt32 = 0xFFB84D

        /// Stop position of `gradientMidHex` in `accentGradient`.
        public static let gradientMidLocation: Double = 0.55

        public static let canvas = Color(hex: canvasHex)
        public static let surface = Color(hex: surfaceHex)
        public static let textPrimary = Color(hex: textPrimaryHex)
        public static let textSecondary = Color(hex: textSecondaryHex)
        public static let textTertiary = Color(hex: textTertiaryHex)
        public static let accent = Color(hex: accentHex)
        public static let spark = Color(hex: sparkHex)
        public static let success = Color(hex: successHex)
        public static let warning = Color(hex: warningHex)

        /// Violet → rose. Reserved for playback progress and the wordmark.
        public static var accentGradient: LinearGradient {
            LinearGradient(
                stops: [
                    .init(color: accent, location: 0),
                    .init(color: Color(hex: gradientMidHex), location: gradientMidLocation),
                    .init(color: spark, location: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: Spacing

    public enum Spacing {
        public static let xs: CGFloat = 8
        public static let s: CGFloat = 16
        public static let m: CGFloat = 24
        public static let l: CGFloat = 40
        public static let xl: CGFloat = 80

    }

    // MARK: Radius

    public enum Radius {
        public static let card: CGFloat = 14
    }

    // MARK: Typography (tvOS text styles only)

    public enum Typography {
        /// Semantic text styles: they resolve to the platform's own sizes (76/38/31/29/25/23 pt on tvOS).
        /// Title 1, bold.
        public static let title: Font = .title.bold()
        /// Headline.
        public static let sectionTitle: Font = .headline
        /// Callout.
        public static let callout: Font = .callout
        /// Body.
        public static let body: Font = .body
        /// Caption 1.
        public static let caption: Font = .caption
        /// Caption 2.
        public static let caption2: Font = .caption2
    }

    // MARK: Focus

    public enum Focus {
        /// Extra brightness on a focused image, on top of the system effect.
        public static let imageBrightness: Double = 0.06
    }

    // MARK: Scrims (fixed gradients over backdrops)

    public enum Scrim {
        public static let leftOpacities: [Double] = [0.96, 0.78, 0]
        public static let leftLocations: [Double] = [0, 0.32, 0.7]
        public static let bottomOpacities: [Double] = [1, 0.92, 0]
        public static let bottomLocations: [Double] = [0, 0.22, 0.6]
        public static let topOpacities: [Double] = [0.8, 0]
        public static let topLocations: [Double] = [0, 0.24]
    }

    // MARK: Placeholder artwork (mockup `.art`)

    public enum Placeholder {
        public static let saturationTop: Double = 0.62
        public static let lightnessTop: Double = 0.36
        public static let saturationBottom: Double = 0.54
        public static let lightnessBottom: Double = 0.13
        public static let hueSpread: Double = 36
        public static let highlightOpacity: Double = 0.22
        public static let bottomShadeOpacity: Double = 0.65
        public static let initialOpacity: Double = 0.10
        /// Initial glyph size relative to the smaller side of the artwork.
        public static let initialScale: Double = 0.85
        public static let initialOffsetX: Double = 0.03
        public static let initialOffsetY: Double = -0.08
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
