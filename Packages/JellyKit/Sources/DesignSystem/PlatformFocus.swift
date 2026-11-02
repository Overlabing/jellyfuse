import SwiftUI

/// The only place that knows how a focusable card or section behaves per platform.
/// Adding iOS / macOS behavior means editing this file, not the components.
extension View {
    /// Card-like button whose label is the ARTWORK ALONE: `.card` is the Apple TV app behavior —
    /// the whole platter lifts and tilts with the remote touchpad. `.borderless` is wrong (it zooms
    /// the image inside its own frame), and the caption must stay OUTSIDE the label.
    func cardButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(.card)
        #else
        buttonStyle(.plain)
        #endif
    }

    /// Chip / pill button: system capsule style (focus inversion on tvOS).
    func capsuleButtonStyle() -> some View {
        buttonStyle(.bordered).buttonBorderShape(.capsule)
    }

    /// Groups children so directional focus moves between blocks predictably (tvOS / macOS focus engine).
    func focusBlock() -> some View {
        #if os(tvOS) || os(macOS)
        focusSection()
        #else
        self
        #endif
    }
}

