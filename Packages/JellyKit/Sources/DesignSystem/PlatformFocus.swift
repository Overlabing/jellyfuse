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
        buttonStyle(PressableCardStyle())
        #endif
    }

    /// Button whose label is a circle (cast portraits): the system `.card` platter would show square
    /// corners behind a round image, so tvOS uses `.borderless` (the label itself lifts) with a circular hover shape.
    @ViewBuilder
    func roundButtonStyle() -> some View {
        #if os(tvOS)
        if #available(tvOS 18, *) {
            buttonStyle(.borderless).contentShape(.hoverEffect, Circle())
        } else {
            buttonStyle(.borderless)
        }
        #else
        buttonStyle(.plain)
        #endif
    }

    /// Chip / pill button: system capsule style (focus inversion on tvOS).
    /// `isProminent`: the filled primary action on touch platforms (tvOS keeps its focus inversion for every pill).
    @ViewBuilder
    func capsuleButtonStyle(isProminent: Bool = false) -> some View {
        #if os(tvOS)
        buttonStyle(.bordered).buttonBorderShape(.capsule)
        #else
        if isProminent {
            buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(Design.Palette.accent)
        } else {
            buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
        #endif
    }

    /// Names the region the default focus is resolved in (tvOS / macOS focus engine); nothing on touch platforms.
    public func platformFocusScope(_ namespace: Namespace.ID) -> some View {
        #if os(tvOS) || os(macOS)
        focusScope(namespace)
        #else
        self
        #endif
    }

    /// Asks for the initial focus inside `namespace`; nothing on touch platforms.
    public func platformDefaultFocus(_ prefers: Bool = true, in namespace: Namespace.ID) -> some View {
        #if os(tvOS) || os(macOS)
        prefersDefaultFocus(prefers, in: namespace)
        #else
        self
        #endif
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


#if !os(tvOS)
/// Touch card: the artwork dips slightly under the finger (no focus effect to lean on).
struct PressableCardStyle: ButtonStyle {
    static let pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Self.pressedScale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#if !os(macOS)
extension View {
    /// `focusSection()` is a tvOS / macOS focus-engine API; on iOS the sections are meaningless, so it is a no-op.
    /// Lets shared views (the player's content panel) keep calling it.
    func focusSection() -> some View { self }
}
#endif
#endif
