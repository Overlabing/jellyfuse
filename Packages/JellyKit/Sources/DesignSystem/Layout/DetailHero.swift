import SwiftUI

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
        .heroTextColumn(metrics)
        .padding(.bottom, metrics.heroBottomInset)
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
