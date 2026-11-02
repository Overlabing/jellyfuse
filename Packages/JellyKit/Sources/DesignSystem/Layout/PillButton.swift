import SwiftUI

/// Capsule button with a leading icon. Focus inversion is the system bordered style.
public struct PillButton: View {
    private let title: String
    private let systemImage: String
    private let action: () -> Void

    public init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(Design.Typography.callout.weight(.bold))
        }
        .capsuleButtonStyle()
    }
}

/// Season / filter chip. The selected chip carries an accent check, on top of the system focus effect.
public struct FuseChip: View {
    private let title: String
    private let isSelected: Bool
    private let action: () -> Void

    public init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Spacing.xs) {
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(Design.Palette.accent)
                }
                Text(title)
            }
            .font(Design.Typography.callout.weight(.semibold))
        }
        .capsuleButtonStyle()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Horizontal row of chips, one selected; its own focus section. Room is reserved around the chips for the focus effect.
public struct ChipRow: View {
    @Environment(\.designMetrics) private var metrics
    private let chips: [ChipModel]
    private let selectedId: String?
    private let onSelect: (String) -> Void

    public init(_ chips: [ChipModel], selectedId: String?, onSelect: @escaping (String) -> Void) {
        self.chips = chips
        self.selectedId = selectedId
        self.onSelect = onSelect
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Design.Spacing.s) {
                ForEach(chips) { chip in
                    FuseChip(chip.title, isSelected: chip.id == selectedId) { onSelect(chip.id) }
                }
            }
            .padding(.horizontal, metrics.screenMargin)
            .padding(.vertical, metrics.focusInset)
        }
        .scrollClipDisabled()
        .focusBlock()
    }
}

#if DEBUG
#Preview("PillButton + FuseChip – normal / focus") {
    PreviewFocusScope { namespace in
        VStack(alignment: .leading, spacing: Design.Spacing.l) {
            HStack(spacing: Design.Spacing.m) {
                PillButton("Lecture", systemImage: "play.fill") {}
                    .previewDefaultFocus(in: namespace)
                PillButton("Ma liste", systemImage: "plus") {}
            }
            HStack(spacing: Design.Spacing.s) {
                FuseChip("Saison 1", isSelected: true) {}
                FuseChip("Saison 2", isSelected: false) {}
                FuseChip("Saison 3", isSelected: false) {}
            }
        }
    }
}
#endif
