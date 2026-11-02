import SwiftUI

/// The title as the server's logo image, bottom-left aligned; the title as text when the item has no
/// logo or it fails to load. While the logo loads nothing is drawn, so the text never flashes first.
public struct TitleLogo: View {
    @Environment(\.designMetrics) private var metrics
    private let title: String
    private let logo: URL?

    public init(title: String, logo: URL?) {
        self.title = title
        self.logo = logo
    }

    public var body: some View {
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
