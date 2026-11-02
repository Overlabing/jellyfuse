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

/// Home billboard (fixed-height section, `metrics.billboardHeight`): one static item with title, meta line, two-line synopsis, and two buttons.
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
            Text(model.title)
                .font(Design.Typography.title)
                .foregroundStyle(Design.Palette.textPrimary)
                .lineLimit(2)
            BillboardMeta(parts: model.metaParts())
            Text(model.overview)
                .font(Design.Typography.body)
                .foregroundStyle(Design.Palette.textSecondary)
                .lineLimit(2)
            HStack(spacing: Design.Spacing.m) {
                PillButton(primaryLabel, systemImage: "play.fill", action: onPlay)
                    .prefersDefaultFocus(true, in: focusNamespace)
                PillButton(
                    model.isInList ? String(localized: "Dans ma liste") : String(localized: "Ma liste"),
                    systemImage: model.isInList ? "checkmark" : "plus",
                    action: onToggleList
                )
                if let onOpenDetail {
                    PillButton(String(localized: "Détails"), systemImage: "info.circle", action: onOpenDetail)
                }
            }
            .padding(.top, Design.Spacing.s)
            .focusBlock()
        }
        .frame(width: metrics.billboardTextWidth, alignment: .leading)
        .padding(.leading, metrics.screenMargin)
        .padding(.bottom, Design.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .frame(height: metrics.billboardHeight)
        .background { BackdropView(model.backdrop) }
        .clipped()
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
                    Text(text).font(Design.Typography.body.weight(.bold)).foregroundStyle(Design.Palette.warning)
                case .text(let text):
                    Text(text).font(Design.Typography.body).foregroundStyle(Design.Palette.textSecondary)
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
