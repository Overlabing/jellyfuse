import SwiftUI

/// Full-bleed backdrop under the three fixed scrims (left, bottom, top).
public struct BackdropView: View {
    private let source: ArtworkSource

    public init(_ source: ArtworkSource) {
        self.source = source
    }

    public var body: some View {
        Artwork(source)
            .overlay { scrim(.leading, .trailing, Design.Scrim.leftOpacities, Design.Scrim.leftLocations) }
            .overlay { scrim(.bottom, .top, Design.Scrim.bottomOpacities, Design.Scrim.bottomLocations) }
            .overlay { scrim(.top, .bottom, Design.Scrim.topOpacities, Design.Scrim.topLocations) }
            .accessibilityHidden(true)
    }

    private func scrim(_ start: UnitPoint, _ end: UnitPoint, _ opacities: [Double], _ locations: [Double]) -> some View {
        LinearGradient(
            stops: zip(opacities, locations).map { .init(color: Design.Palette.canvas.opacity($0), location: $1) },
            startPoint: start,
            endPoint: end
        )
    }
}

/// Home billboard (fixed-height section, `metrics.billboardHeight`): one static item with title (logo, text fallback), meta line, two-line synopsis, and two buttons.
public struct Billboard: View {
    @Environment(\.designMetrics) private var metrics
    private let model: BillboardModel
    private let primaryLabel: String
    private let onPlay: () -> Void
    private let onToggleList: () -> Void
    private let onOpenDetail: (() -> Void)?
    private let focusNamespace: Namespace.ID

    public init(
        _ model: BillboardModel,
        primaryLabel: String,
        onPlay: @escaping () -> Void,
        onToggleList: @escaping () -> Void,
        onOpenDetail: (() -> Void)? = nil,
        focusNamespace: Namespace.ID
    ) {
        self.model = model
        self.primaryLabel = primaryLabel
        self.onPlay = onPlay
        self.onToggleList = onToggleList
        self.onOpenDetail = onOpenDetail
        self.focusNamespace = focusNamespace
    }

    public var body: some View {
        // Fixed-height section at the head of the scroll: the text block is laid out inside the
        // frame and the backdrop is only its background, so it can never move the content.
        VStack(alignment: .leading, spacing: Design.Spacing.m) {
            TitleLogo(title: model.title, logo: model.logo)
            BillboardMeta(parts: model.metaParts())
            Text(model.overview)
                .font(Design.Typography.body)
                .foregroundStyle(Design.Palette.textSecondary)
                .lineLimit(2)
            HStack(spacing: metrics.isTouch ? Design.Spacing.xs : Design.Spacing.m) {
                PillButton(primaryLabel, systemImage: "play.fill", isProminent: true, fillsWidth: metrics.isTouch, action: onPlay)
                    .accessibilityIdentifier("home.billboard.play")
                    .platformDefaultFocus(in: focusNamespace)
                PillButton(
                    model.isInList ? String(localized: "Dans ma liste", bundle: .module) : String(localized: "Ma liste", bundle: .module),
                    systemImage: model.isInList ? "checkmark" : "plus",
                    fillsWidth: metrics.isTouch,
                    action: onToggleList
                )
                if let onOpenDetail {
                    PillButton(String(localized: "Détails", bundle: .module), systemImage: "info.circle", fillsWidth: metrics.isTouch, action: onOpenDetail)
                }
            }
            .padding(.top, Design.Spacing.s)
            .focusBlock()
        }
        .heroTextColumn(metrics)
        .padding(.bottom, metrics.heroBottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .frame(height: metrics.billboardHeight)
        .background { BackdropView(model.backdrop) }
        .clipped()
    }
}

extension View {
    /// The text block of a hero: a fixed-width column on the left (tv, iPad), or the full width between the margins (iPhone).
    @ViewBuilder
    func heroTextColumn(_ metrics: Design.Metrics) -> some View {
        if let width = metrics.billboardTextWidth {
            frame(width: width, alignment: .leading).padding(.leading, metrics.screenMargin)
        } else {
            frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, metrics.screenMargin)
        }
    }
}

struct BillboardMeta: View {
    let parts: [BillboardModel.MetaPart]

    var body: some View {
        HStack(spacing: Design.Spacing.s) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    Circle().fill(Design.Palette.textTertiary).frame(width: Design.Spacing.xs / 2, height: Design.Spacing.xs / 2)
                }
                switch part {
                case .rating(let text):
                    Text(text).font(Design.Typography.body.weight(.bold)).foregroundStyle(Design.Palette.warning).lineLimit(1)
                case .text(let text):
                    Text(text).font(Design.Typography.body).foregroundStyle(Design.Palette.textSecondary).lineLimit(1)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Billboard – Lecture focused") {
    PreviewFocusScope { namespace in
        VStack(spacing: 0) {
            Billboard(PreviewData.billboard, primaryLabel: "Lecture", onPlay: {}, onToggleList: {}, focusNamespace: namespace)
            Spacer()
        }
    }
}
#endif
