import DesignSystem
import HomePresentation
import LibraryKit
import SwiftUI

/// The « Filtres et tri » panel: sort field and direction, the two filters, and « Aller à la lettre ».
/// Every choice applies at once; Menu closes the panel. Props in, callbacks out.
struct FilterSortPanel: View {
    @Environment(\.designMetrics) private var metrics
    let sort: LibrarySort
    let filter: LibraryFilter
    let startsAt: String?
    let onSelectField: (LibrarySortField) -> Void
    let onSelectDirection: (SortDirection) -> Void
    let onSetUnwatched: (Bool) -> Void
    let onSetFavorites: (Bool) -> Void
    let onJump: (String) -> Void

    private let letterColumns = Array(repeating: GridItem(.flexible(), spacing: Design.Spacing.s), count: 9)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.l) {
                section(String(localized: "Trier par")) {
                    HStack(spacing: Design.Spacing.s) {
                        ForEach(LibrarySortField.allCases, id: \.self) { field in
                            FuseChip(LibraryGridMapper.fieldLabel(field), isSelected: sort.field == field) { onSelectField(field) }
                        }
                    }
                    HStack(spacing: Design.Spacing.s) {
                        ForEach([SortDirection.ascending, .descending], id: \.self) { direction in
                            FuseChip(LibraryGridMapper.directionLabel(direction), isSelected: sort.direction == direction) {
                                onSelectDirection(direction)
                            }
                        }
                    }
                }
                section(String(localized: "Filtrer")) {
                    HStack(spacing: Design.Spacing.s) {
                        FuseChip(String(localized: "Non vus"), isSelected: filter.unwatchedOnly) { onSetUnwatched(!filter.unwatchedOnly) }
                        FuseChip(String(localized: "Favoris"), isSelected: filter.favoritesOnly) { onSetFavorites(!filter.favoritesOnly) }
                    }
                }
                if sort.supportsLetterJump {
                    section(String(localized: "Aller à la lettre")) {
                        LazyVGrid(columns: letterColumns, alignment: .leading, spacing: Design.Spacing.s) {
                            ForEach(LibraryGridMapper.letters, id: \.self) { letter in
                                FuseChip(letter, isSelected: (startsAt ?? "#") == letter) { onJump(letter) }
                                    .accessibilityLabel(letter == "#" ? String(localized: "Début de la liste") : letter)
                            }
                        }
                    }
                }
            }
            .padding(metrics.screenMargin)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.s) {
            Text(title)
                .font(Design.Typography.sectionTitle)
                .foregroundStyle(Design.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}
