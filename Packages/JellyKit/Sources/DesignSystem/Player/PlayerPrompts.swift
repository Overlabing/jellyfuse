import SwiftUI

/// What the « Épisode suivant » card shows.
public struct UpNextCardModel: Sendable, Equatable {
    /// `S1E5 · Titre`.
    public let title: String
    public let thumbnail: ArtworkSource
    /// Seconds before the next episode starts by itself.
    public let countdown: Int
    /// On the closing credits, Menu lets the viewer watch them instead.
    public let offersWatchCredits: Bool

    public init(title: String, thumbnail: ArtworkSource, countdown: Int, offersWatchCredits: Bool) {
        self.title = title
        self.thumbnail = thumbnail
        self.countdown = countdown
        self.offersWatchCredits = offersWatchCredits
    }
}

/// The contextual actions floating over the video: « Passer l'intro » at the bottom left, the next-episode
/// card at the bottom right. Neither takes the focus: the remote bridge stays the only focusable thing and
/// routes Select (do it) and Menu (dismiss) to the one on screen. They rise above the display while it shows.
public struct PlayerPrompts: View {
    @Environment(\.designMetrics) private var metrics
    private let skipLabel: String?
    private let upNext: UpNextCardModel?
    private let isOSDVisible: Bool

    /// `skipLabel`: « Passer l'intro » or « Passer le générique » while in such a segment, else nil.
    public init(skipLabel: String?, upNext: UpNextCardModel?, isOSDVisible: Bool) {
        self.skipLabel = skipLabel
        self.upNext = upNext
        self.isOSDVisible = isOSDVisible
    }

    public var body: some View {
        HStack(alignment: .bottom) {
            if let skipLabel { SkipButton(label: skipLabel).transition(.opacity) }
            Spacer()
            if let upNext { UpNextCard(model: upNext).transition(.move(edge: .trailing).combined(with: .opacity)) }
        }
        .padding(.horizontal, metrics.screenMargin)
        .padding(.bottom, isOSDVisible ? 320 : 100)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.easeOut(duration: 0.25), value: isOSDVisible)
        .animation(.easeOut(duration: 0.25), value: skipLabel)
        .animation(.easeOut(duration: 0.25), value: upNext == nil)
        .allowsHitTesting(false)
    }
}

private struct SkipButton: View {
    let label: String

    var body: some View {
        Label(label, systemImage: "forward.end.fill")
            .font(Design.Typography.callout.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, Design.Spacing.m)
            .padding(.vertical, Design.Spacing.s)
            .background(.black.opacity(0.65), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 2))
    }
}

private struct UpNextCard: View {
    let model: UpNextCardModel

    var body: some View {
        HStack(spacing: Design.Spacing.s) {
            Artwork(model.thumbnail)
                .frame(width: 256, height: 144)
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.card))
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                Text("Épisode suivant", bundle: .module)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Palette.textSecondary)
                Text(model.title)
                    .font(Design.Typography.callout.weight(.bold))
                    .lineLimit(2)
                Text(hint)
                    .font(Design.Typography.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                Text(model.offersWatchCredits ? String(localized: "Menu : regarder le générique", bundle: .module) : String(localized: "Menu : ignorer", bundle: .module))
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Palette.textSecondary)
            }
            .frame(width: 320, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(Design.Spacing.s)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: Design.Radius.card + Design.Spacing.s))
        .accessibilityElement(children: .combine)
    }

    private var hint: String {
        let countdown = model.countdown
        return String(localized: "Lecture dans \(countdown) s · cliquer pour lancer", bundle: .module)
    }
}

#if DEBUG
#Preview("Prompts") {
    ZStack {
        LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
        PlayerPrompts(
            skipLabel: "Passer l'intro",
            upNext: UpNextCardModel(title: "S2E6 · Fréquence zéro", thumbnail: ArtworkSource(url: nil, placeholderTitle: "Fréquences"), countdown: 7, offersWatchCredits: true),
            isOSDVisible: false
        )
    }
    .ignoresSafeArea()
}
#endif
