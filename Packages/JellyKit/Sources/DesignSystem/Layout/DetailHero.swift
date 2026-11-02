import SwiftUI

/// The title as the server's logo image, bottom-left aligned; the title as text when the item has no
/// logo or it fails to load. While the logo loads nothing is drawn, so the text never flashes first.
struct TitleLogo: View {
    @Environment(\.designMetrics) private var metrics
    let title: String
    let logo: URL?

    var body: some View {
        Group {
            if let logo {
                AsyncImage(url: logo) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit()
                    case .failure: TitleText(title: title)
                    default: Color.clear
                    }
                }
                .frame(maxWidth: metrics.detailLogo.width, maxHeight: metrics.detailLogo.height, alignment: .bottomLeading)
            } else {
                TitleText(title: title)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct TitleText: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Design.Typography.title)
            .foregroundStyle(Design.Palette.textPrimary)
            .lineLimit(2)
    }
}

/// Header of the detail screen: backdrop under the three scrims, title logo (text fallback), meta
/// line, synopsis and the action buttons. The caller sets the height; the content sits bottom-left.
public struct DetailHero<Actions: View>: View {
    @Environment(\.designMetrics) private var metrics
    private let model: DetailHeaderModel
    private let actions: Actions

    public init(_ model: DetailHeaderModel, @ViewBuilder actions: () -> Actions) {
        self.model = model
        self.actions = actions()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.m) {
            TitleLogo(title: model.title, logo: model.logo)
            BillboardMeta(parts: model.metaParts())
            if !model.overview.isEmpty {
                Text(model.overview)
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Palette.textSecondary)
                    .lineLimit(3)
            }
            actions
                .padding(.top, Design.Spacing.s)
                .focusBlock()
        }
        .frame(width: metrics.billboardTextWidth, alignment: .leading)
        .padding(.leading, metrics.screenMargin)
        .padding(.bottom, Design.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background { BackdropView(model.backdrop) }
        .clipped()
    }
}

#if DEBUG
#Preview("DetailHero – title as text, Lecture focused") {
    PreviewFocusScope { namespace in
        DetailHero(PreviewData.detailHeader) {
            HStack(spacing: Design.Spacing.m) {
                PillButton("Lecture", systemImage: "play.fill") {}
                    .previewDefaultFocus(in: namespace)
                PillButton("Ma liste", systemImage: "plus") {}
            }
        }
        .frame(height: Design.Metrics.tv.detailHeroHeight)
    }
}
#endif
