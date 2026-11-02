import DesignSystem
import SwiftUI

/// Tabs that are not built yet: a title, nothing else (ui-plan lots 3.5 to 3.7).
struct PlaceholderScreen: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Design.Typography.title)
            .foregroundStyle(Design.Palette.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
