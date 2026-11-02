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
        public var billboardTextWidth: CGFloat
        /// Detail header of a series (a movie's fills the screen): room above the seasons.
        public var detailHeroHeight: CGFloat
        /// Largest area of the title logo on the detail header.
        public var detailLogo: CGSize
        /// Diameter of a cast portrait, and the width of its card (the caption is wider than the portrait).
        public var castPortrait: CGFloat
        public var castCardWidth: CGFloat

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
            billboardTextWidth: 860,
            detailHeroHeight: 640,
            detailLogo: CGSize(width: 640, height: 160),
            castPortrait: 150,
            castCardWidth: 190
        )
    }
}

private struct MetricsKey: EnvironmentKey {
    // Only tvOS metrics exist for now; iOS / iPadOS / macOS will add theirs and pick by platform here.
    static let defaultValue = Design.Metrics.tv
}

extension EnvironmentValues {
    public var designMetrics: Design.Metrics {
        get { self[MetricsKey.self] }
        set { self[MetricsKey.self] = newValue }
    }
}
