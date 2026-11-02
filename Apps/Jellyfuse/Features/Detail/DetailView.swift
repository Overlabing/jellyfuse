import DesignSystem
import HomePresentation
import SwiftUI

/// Pure detail layout (detail-movie.html / detail-series.html): header with title logo and actions,
/// then, for a series, the season chips and the episodes of the selected season, then the cast. Props in, callbacks out.
struct DetailView: View {
    @Environment(\.designMetrics) private var metrics
    @Namespace private var focusNamespace
    let content: DetailContent?
    let isLoadingChildren: Bool
    let failureMessage: String?
    let actionFailureMessage: String?
    let onPlay: () -> Void
    let onToggleFavorite: () -> Void
    let onToggleWatched: () -> Void
    let onSelectSeason: (String) -> Void
    let onPlayEpisode: (String) -> Void
    /// `(episodeId, watched)`: from the long-press menu of an episode.
    let onSetEpisodeWatched: (String, Bool) -> Void
    let onOpenPerson: (PersonModel) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let content {
                    hero(content)
                    if content.isSeries { episodes(content) }
                    if !content.people.isEmpty { cast(content.people) }
                } else {
                    placeholder
                }
            }
            .padding(.bottom, metrics.safeVertical)
        }
        .focusScope(focusNamespace)
        .ignoresSafeArea(edges: [.top, .horizontal])
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func hero(_ content: DetailContent) -> some View {
        let header = DetailHero(content.header) {
            VStack(alignment: .leading, spacing: Design.Spacing.s) {
                HStack(spacing: Design.Spacing.m) {
                    PillButton(content.playLabel, systemImage: "play.fill", action: onPlay)
                        .disabled(content.playTarget == nil)
                        .prefersDefaultFocus(true, in: focusNamespace)
                    PillButton(
                        content.isFavorite ? String(localized: "Dans ma liste") : String(localized: "Ma liste"),
                        systemImage: content.isFavorite ? "checkmark" : "plus",
                        action: onToggleFavorite
                    )
                    if let isWatched = content.isWatched {
                        PillButton(
                            isWatched ? String(localized: "Vu") : String(localized: "Marquer vu"),
                            systemImage: isWatched ? "checkmark" : "eye",
                            action: onToggleWatched
                        )
                    }
                }
                if let actionFailureMessage {
                    Text(actionFailureMessage)
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Palette.textSecondary)
                }
            }
        }
        if content.isSeries {
            header.frame(height: metrics.detailHeroHeight)
        } else {
            header.containerRelativeFrame(.vertical)
        }
    }

    @ViewBuilder
    private func episodes(_ content: DetailContent) -> some View {
        if !content.seasons.isEmpty {
            ChipRow(content.seasons, selectedId: content.selectedSeasonId, onSelect: onSelectSeason)
        }
        if !content.episodes.isEmpty {
            Shelf(title: nil, items: content.episodes) { model in
                LandscapeCard(model, onToggleWatched: { onSetEpisodeWatched(model.id, !model.isWatched) }) {
                    onPlayEpisode(model.id)
                }
            }
        } else if let failureMessage {
            status(failureMessage)
        } else if isLoadingChildren {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.xl)
        }
    }

    private func cast(_ people: [PersonModel]) -> some View {
        Shelf(title: String(localized: "Distribution"), items: people) { person in
            CastCard(person) { onOpenPerson(person) }
        }
            .padding(.top, metrics.gridRowGap - 2 * metrics.focusInset)
    }

    private var placeholder: some View {
        ZStack {
            BackdropView(ArtworkSource(url: nil, placeholderTitle: ""))
            if let failureMessage {
                status(failureMessage)
            } else {
                ProgressView()
            }
        }
        .containerRelativeFrame(.vertical)
        .accessibilityHidden(failureMessage == nil)
    }

    private func status(_ message: String) -> some View {
        Text(message)
            .font(Design.Typography.body)
            .foregroundStyle(Design.Palette.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Spacing.xl)
    }
}
