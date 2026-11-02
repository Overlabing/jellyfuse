import SwiftUI

public enum PlayerTab: String, Sendable, CaseIterable, Identifiable {
    case info, audio, subtitles, chapters

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .info: String(localized: "Infos", bundle: .module)
        case .audio: String(localized: "Audio", bundle: .module)
        case .subtitles: String(localized: "Sous-titres", bundle: .module)
        case .chapters: String(localized: "Chapitres", bundle: .module)
        }
    }
}

/// A row of the Audio or Sous-titres tab.
public struct TrackRow: Sendable, Equatable, Identifiable {
    /// Jellyfin stream index; `TrackRow.offID` for « Désactivés ».
    public let id: Int
    public let title: String
    public let detail: String
    public let isSelected: Bool

    public static let offID = -1

    public init(id: Int, title: String, detail: String = "", isSelected: Bool) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isSelected = isSelected
    }

    /// The subtitle list: « Désactivés » first, checked when no subtitle track is.
    public static func subtitleList(_ tracks: [TrackRow]) -> [TrackRow] {
        let off = TrackRow(id: offID, title: String(localized: "Désactivés", bundle: .module), isSelected: !tracks.contains { $0.isSelected })
        return [off] + tracks
    }
}

/// A row of the Chapitres tab.
public struct ChapterRow: Sendable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    /// `0:19:24`.
    public let time: String
    public let startSeconds: Double
    /// The playhead is in this chapter.
    public let isCurrent: Bool

    public init(id: Int, title: String, time: String, startSeconds: Double, isCurrent: Bool) {
        self.id = id
        self.title = title
        self.time = time
        self.startSeconds = startSeconds
        self.isCurrent = isCurrent
    }

    /// Unnamed chapters read « Chapitre N ».
    public static func rows(names: [String?], starts: [Double], position: Double) -> [ChapterRow] {
        let current = ChapterMarks.currentIndex(starts: starts, position: position)
        return starts.indices.map { index in
            let name = names[index].flatMap { $0.isEmpty ? nil : $0 }
            return ChapterRow(
                id: index, title: name ?? String(localized: "Chapitre \(index + 1)", bundle: .module),
                time: OSDModel.clock(starts[index]), startSeconds: starts[index], isCurrent: index == current
            )
        }
    }
}

/// What the Infos tab says.
public struct InfoContent: Sendable, Equatable {
    public let title: String
    /// `2021 · 1 h 52 · Science-fiction`; empty when nothing is known.
    public let facts: String
    public let synopsis: String

    public init(title: String, facts: String = "", synopsis: String = "") {
        self.title = title
        self.facts = facts
        self.synopsis = synopsis
    }
}

/// Everything the panel shows, already formatted.
public struct ContentTabsModel: Sendable, Equatable {
    public var info: InfoContent
    public var audio: [TrackRow]
    /// Without « Désactivés »: `TrackRow.subtitleList` adds it.
    public var subtitles: [TrackRow]
    public var chapters: [ChapterRow]
    /// False when the stream is transcoded: the server chose the tracks and they cannot be switched here.
    public var canSwitchTracks: Bool

    public init(info: InfoContent, audio: [TrackRow], subtitles: [TrackRow], chapters: [ChapterRow], canSwitchTracks: Bool) {
        self.info = info
        self.audio = audio
        self.subtitles = subtitles
        self.chapters = chapters
        self.canSwitchTracks = canSwitchTracks
    }

    /// Tabs that have something to show: Chapitres hides without chapters, the track tabs without tracks.
    public var tabs: [PlayerTab] {
        PlayerTab.allCases.filter { tab in
            switch tab {
            case .info: true
            case .audio: !audio.isEmpty
            case .subtitles: !subtitles.isEmpty
            case .chapters: !chapters.isEmpty
            }
        }
    }
}

/// The content panel of the player: tabs over one list at a time. Props in, callbacks out. It is a real
/// SwiftUI focus surface: while it is on screen the remote bridge gives up the focus (see `RemoteInputView`).
public struct ContentTabs: View {
    private let model: ContentTabsModel
    private let selection: PlayerTab
    private let onSelectTab: (PlayerTab) -> Void
    private let onSelectAudio: (Int) -> Void
    /// `TrackRow.offID` turns the subtitles off.
    private let onSelectSubtitle: (Int) -> Void
    private let onSelectChapter: (Double) -> Void
    /// Menu or up from the tab row: the screen animates the panel away, then dismisses it.
    private let onClose: @MainActor () -> Void

    public init(
        model: ContentTabsModel, selection: PlayerTab, onSelectTab: @escaping (PlayerTab) -> Void,
        onSelectAudio: @escaping (Int) -> Void, onSelectSubtitle: @escaping (Int) -> Void,
        onSelectChapter: @escaping (Double) -> Void, onClose: @escaping @MainActor () -> Void
    ) {
        self.model = model
        self.selection = selection
        self.onSelectTab = onSelectTab
        self.onSelectAudio = onSelectAudio
        self.onSelectSubtitle = onSelectSubtitle
        self.onSelectChapter = onSelectChapter
        self.onClose = onClose
    }

    @FocusState private var focusedTab: PlayerTab?

    public var body: some View {
        pinned
    }

    /// Glued to the top edge, centered horizontally; the rest of the screen stays empty (video behind).
    private var pinned: some View {
        panel
            .padding(.top, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.m) {
            HStack(spacing: Design.Spacing.s) {
                Spacer(minLength: 0)
                ForEach(model.tabs) { tab in
                    Button(tab.title) { onSelectTab(tab) }
                        .capsuleButtonStyle()
                        .lineLimit(1)
                        .fixedSize()
                        .fontWeight(tab == selection ? .bold : .regular)
                        .opacity(tab == selection ? 1 : 0.7)
                        .focused($focusedTab, equals: tab)
                        .accessibilityAddTraits(tab == selection ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            #if os(tvOS)
            // Nothing is above the tab row: Menu and up close the panel (the list below climbs back here first).
            .onExitCommand { onClose() }
            // Left / right are the focus engine's alone (one mechanism: a manual step on top of it jumped two tabs
            // on the real pad); the focus sections keep them inside the row. Only up, which has nothing above, is ours.
            .onMoveCommand { if $0 == .up { onClose() } }
            #endif
            .focusSection()
            content
                .focusSection()
                #if os(tvOS)
                // Menu from inside the list climbs back to the tab (like the system tab bar) instead of closing
                // the panel: the event is consumed here, so the presentation never sees it. From the tabs, which
                // are outside this view, Menu is not consumed and dismisses the panel.
                .onExitCommand { focusedTab = selection }
                #endif
        }
        .padding(Design.Spacing.l)
        .frame(width: 1400, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        .focusSection()
        .defaultFocus($focusedTab, selection)
        // The selection follows the focus (like the system tab bar): no click needed to open a tab.
        .onChange(of: focusedTab) { _, tab in if let tab { onSelectTab(tab) } }
    }

    @ViewBuilder private var content: some View {
        switch selection {
        case .info: info
        case .audio: tracks(model.audio, onSelect: onSelectAudio)
        case .subtitles: tracks(TrackRow.subtitleList(model.subtitles), onSelect: onSelectSubtitle)
        case .chapters: chapters
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.s) {
            Text(model.info.title).font(Design.Typography.callout.weight(.bold))
            if !model.info.facts.isEmpty {
                Text(model.info.facts).font(Design.Typography.caption).foregroundStyle(Design.Palette.textSecondary)
            }
            if !model.info.synopsis.isEmpty {
                Text(model.info.synopsis).font(Design.Typography.body).lineLimit(6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.Spacing.s)
    }

    @ViewBuilder private func tracks(_ rows: [TrackRow], onSelect: @escaping (Int) -> Void) -> some View {
        if model.canSwitchTracks {
            list(rows.map { Row(id: $0.id, title: $0.title, detail: $0.detail, isMarked: $0.isSelected) }, onSelect: { onSelect($0) })
        } else {
            Text("Les pistes sont choisies par le serveur pendant un transcodage.", bundle: .module)
                .font(Design.Typography.body)
                .foregroundStyle(Design.Palette.textSecondary)
                .padding(Design.Spacing.s)
        }
    }

    private var chapters: some View {
        let starts = Dictionary(uniqueKeysWithValues: model.chapters.map { ($0.id, $0.startSeconds) })
        return list(
            model.chapters.map { Row(id: $0.id, title: $0.title, detail: $0.time, isMarked: $0.isCurrent) },
            onSelect: { id in onSelectChapter(starts[id] ?? 0) }
        )
    }

    private struct Row: Identifiable {
        let id: Int
        let title: String
        let detail: String
        let isMarked: Bool
    }

    private func list(_ rows: [Row], onSelect: @escaping (Int) -> Void) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Design.Spacing.xs) {
                    ForEach(rows) { row in
                        Button { onSelect(row.id) } label: {
                            HStack(spacing: Design.Spacing.s) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Design.Palette.accent)
                                    .opacity(row.isMarked ? 1 : 0)
                                    .accessibilityHidden(true)
                                Text(row.title).lineLimit(1)
                                Spacer(minLength: Design.Spacing.s)
                                Text(row.detail)
                                    .font(Design.Typography.caption.monospacedDigit())
                                    .foregroundStyle(Design.Palette.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .capsuleButtonStyle()
                        .accessibilityAddTraits(row.isMarked ? .isSelected : [])
                        .id(row.id)
                    }
                }
                // Room for the focused row to grow (scale + lift) without being cut by the scroll view.
                .padding(.horizontal, Design.Spacing.m)
                .padding(.vertical, Design.Spacing.s)
            }
            .scrollClipDisabled()
            .frame(maxHeight: 460)
            // Focus effects may overflow sideways, but a scrolled row must not draw over the tab row.
            .mask(Rectangle().padding(.horizontal, -Design.Spacing.l))
            .onAppear {
                if let marked = rows.first(where: \.isMarked) { proxy.scrollTo(marked.id, anchor: .center) }
            }
        }
    }
}
