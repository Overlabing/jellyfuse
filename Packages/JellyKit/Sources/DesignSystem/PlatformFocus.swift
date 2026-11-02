import SwiftUI

/// The only place that knows how a focusable card or section behaves per platform.
/// Adding iOS / macOS behavior means editing this file, not the components.
extension View {
    /// Card-like button: system focus effect on tvOS (lift, shadow, parallax); plain tap target elsewhere.
    func cardButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(.borderless)
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
