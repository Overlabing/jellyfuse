import SwiftUI

extension Design {
    /// Layout metrics of one platform family. Components read them from the environment, so a touch UI
    /// supplies its own `Metrics` (`.environment(\.designMetrics, ...)`) without touching components or tokens.
    public struct Metrics: Sendable, Equatable {
        public var screenMargin: CGFloat
        public var safeVertical: CGFloat
        public var shelfGap: CGFloat
        public var gridRowGap: CGFloat
        /// Room a shelf reserves above and below its cards for the focus effect.
        public var focusInset: CGFloat
        public var poster: CGSize
        public var landscape: CGSize
        public var progressBarHeight: CGFloat
        public var watchedFlag: CGFloat
        public var wordmarkHeight: CGFloat
        public var billboardHeight: CGFloat
        /// Detail header of a series (a movie's fills the screen): room above the seasons.
        public var detailHeroHeight: CGFloat
        /// Largest area of the title logo on the detail header.
        public var detailLogo: CGSize
        /// Diameter of a cast portrait, and the width of its card (the caption is wider than the portrait).
        public var castPortrait: CGFloat
        public var castCardWidth: CGFloat
        /// Width of the text column of the billboard / detail header; nil = the full width between the margins (touch).
        public var billboardTextWidth: CGFloat?
        /// Room under the text of the billboard / detail header.
        public var heroBottomInset: CGFloat
        /// Touch platforms: no focus engine, so a movie's detail header has a fixed height instead of filling the screen.
        public var isTouch: Bool
        /// Title under a card.
        public var cardTitleFont: Font

        /// tvOS, 1920×1080 pt, HIG safe area (80 pt sides, 60 pt top/bottom). Source: ui-plan §3.3 + mockups.
        public static let tv = Metrics(
            screenMargin: 80,
            safeVertical: 60,
            shelfGap: 40,
            gridRowGap: 100,
            focusInset: 40,
            poster: CGSize(width: 260, height: 390),
            landscape: CGSize(width: 410, height: 231),
            progressBarHeight: 8,
            watchedFlag: 44,
            wordmarkHeight: 40,
            billboardHeight: 665,
            detailHeroHeight: 640,
            detailLogo: CGSize(width: 640, height: 160),
            castPortrait: 150,
            castCardWidth: 190,
            billboardTextWidth: 860,
            heroBottomInset: Design.Spacing.xl,
            isTouch: false,
            cardTitleFont: Design.Typography.body.weight(.semibold)
        )

        /// iPhone (compact width, ~390 pt): a poster 3 per screen, 16 pt margins.
        public static let phone = Metrics(
            screenMargin: 16,
            safeVertical: 16,
            shelfGap: 12,
            gridRowGap: 20,
            focusInset: 0,
            poster: CGSize(width: 120, height: 180),
            landscape: CGSize(width: 240, height: 135),
            progressBarHeight: 4,
            watchedFlag: 26,
            wordmarkHeight: 28,
            billboardHeight: 480,
            detailHeroHeight: 440,
            detailLogo: CGSize(width: 260, height: 80),
            castPortrait: 72,
            castCardWidth: 88,
            billboardTextWidth: nil,
            heroBottomInset: Design.Spacing.m,
            isTouch: true,
            cardTitleFont: Design.Typography.callout.weight(.semibold)
        )

        /// iPad (regular width) and large iPhones in landscape.
        public static let pad = Metrics(
            screenMargin: 32,
            safeVertical: 24,
            shelfGap: 20,
            gridRowGap: 28,
            focusInset: 0,
            poster: CGSize(width: 180, height: 270),
            landscape: CGSize(width: 320, height: 180),
            progressBarHeight: 5,
            watchedFlag: 30,
            wordmarkHeight: 34,
            billboardHeight: 560,
            detailHeroHeight: 560,
            detailLogo: CGSize(width: 420, height: 120),
            castPortrait: 96,
            castCardWidth: 116,
            billboardTextWidth: 560,
            heroBottomInset: Design.Spacing.l,
            isTouch: true,
            cardTitleFont: Design.Typography.callout.weight(.semibold)
        )
    }
}

private struct MetricsKey: EnvironmentKey {
    #if os(tvOS)
    static let defaultValue = Design.Metrics.tv
    #else
    static let defaultValue = Design.Metrics.phone
    #endif
}

extension EnvironmentValues {
    public var designMetrics: Design.Metrics {
        get { self[MetricsKey.self] }
        set { self[MetricsKey.self] = newValue }
    }
}

extension View {
    /// Picks the touch metrics from the size class: iPad / large landscape (regular width) or iPhone (compact).
    /// A no-op on tvOS, whose metrics are the environment default.
    public func adaptiveDesignMetrics() -> some View {
        modifier(AdaptiveMetrics())
    }
}

private struct AdaptiveMetrics: ViewModifier {
    #if !os(tvOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    func body(content: Content) -> some View {
        #if os(tvOS)
        content
        #else
        content.environment(\.designMetrics, sizeClass == .regular ? .pad : .phone)
        #endif
    }
}
