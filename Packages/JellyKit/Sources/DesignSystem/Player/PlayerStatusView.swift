import SwiftUI

/// Full-screen player states with no video: the spinner while it loads, the failure message when it cannot play.
public struct PlayerStatusView: View {
    public enum Kind: Equatable, Sendable {
        case loading
        case failed(title: String, message: String)
    }

    private let kind: Kind

    public init(_ kind: Kind) { self.kind = kind }

    public var body: some View {
        switch kind {
        case .loading:
            ProgressView()
                .scaleEffect(2)
                .tint(.white)
                .accessibilityLabel(Text("Chargement"))
        case .failed(let title, let message):
            VStack(spacing: Design.Spacing.s) {
                Text(title).font(Design.Typography.title)
                Text(message)
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                Text("Appuyez sur Menu pour revenir.")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Palette.textTertiary)
            }
            .foregroundStyle(.white)
            .padding(Design.Spacing.xl)
        }
    }
}
