import DesignSystem
import HomePresentation
import PlayerCore
import PlayerPresentation
import SwiftUI

/// Plays one item, reporting it to the server. The Siri Remote drives the transport (see `RemoteInputView`);
/// Menu closes the display, then the player.
struct PlayerScreen: View {
    let onClose: () -> Void
    /// The next episode is starting (Select on its card, the countdown, or the end of the file).
    let onPlayNext: (PlayTarget) -> Void
    @State private var tiles: TrickplayTiles
    @State private var model: PlaybackModel
    @State private var transport: TransportController
    @State private var tab = PlayerTab.info
    @State private var lastPressRawValue: Int?
    /// Debug overlay: launch with `-stats YES`.
    #if DEBUG
    private let showsStats = UserDefaults.standard.bool(forKey: "stats")
    #else
    private let showsStats = false
    #endif
    @State private var focusProbe = FocusProbe()

    init(target: PlayTarget, services: PlaybackServices, onClose: @escaping () -> Void, onPlayNext: @escaping (PlayTarget) -> Void) {
        self.onClose = onClose
        self.onPlayNext = onPlayNext
        let itemId = target.id
        _tiles = State(initialValue: TrickplayTiles(urlForTile: { width, index in
            services.trickplayTileURL(itemId: itemId, width: width, index: index)
        }))
        let model = PlaybackModel(target: target, services: services)
        _model = State(initialValue: model)
        _transport = State(initialValue: TransportController(driver: .init(
            position: { model.position }, duration: { model.duration }, isPaused: { model.isPaused },
            seek: { model.seek(to: $0) }, setPaused: { model.setPaused($0) }
        )))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player = model.player, let url = model.streamURL, model.failure == nil {
                MpvPlayerView(player: player, startURL: url)
                    .ignoresSafeArea()
            }
            PlayerOSD(state: transport.state, model: osdModel, scrubThumbnail: scrubThumbnail)
                .ignoresSafeArea()
            PlayerPrompts(skipLabel: skipLabel, upNext: upNextCard, isOSDVisible: transport.visibility.isVisible)
                .ignoresSafeArea()
            status
            if showsStats { stats }
        }
        .animation(.easeOut(duration: 0.2), value: model.isBuffering)
        // The panel is a presentation: the platform gives its content the focus and Menu dismisses it (not the
        // player under it). The bridge steps aside while it is up and takes the focus back when it goes.
        .fullScreenCover(isPresented: Binding(get: { transport.isPanelOpen }, set: { if !$0 { transport.closePanel() } })) {
            PanelCover(onDismiss: { transport.closePanel() }) { close in panel(close: close) }
        }
        .overlay { RemoteInputView(handlers: remoteHandlers, isActive: !transport.isPanelOpen).ignoresSafeArea() }
        .task(id: transport.visibility.deadline) { await hideWhenIdle() }
        .task(id: transport.skipFeedback?.token) { await clearSkipFeedback() }
        .onChange(of: model.isPaused) { _, paused in transport.pausedChanged(paused) }
        .task(id: scrubTile) { if let sheet = model.trickplay, let scrubTile { await tiles.load(tile: scrubTile, of: sheet) } }
        .onChange(of: model.autoplay) { _, next in if let next { playNext(next) } }
        .onChange(of: model.phase) { _, phase in
            guard phase == .ended else { return }
            if let next = model.episodeAtEnd { playNext(next) } else { onClose() }
        }
        .onDisappear { model.stop() }
    }

    private var osdModel: OSDModel {
        OSDModel(
            title: model.heading, position: transport.displayedPosition, duration: model.duration,
            isScrubbing: transport.isScrubbing,
            chapterMarks: ChapterMarks.fractions(starts: model.chapters.map(\.startSeconds), duration: model.duration),
            chapterTitle: chapterTitle
        )
    }

    /// The chapter under the playhead (or the scrub preview), for the scrub bubble.
    private var chapterTitle: String? {
        let chapters = model.chapters
        guard let index = ChapterMarks.currentIndex(starts: chapters.map(\.startSeconds), position: transport.displayedPosition) else { return nil }
        return ChapterRow.rows(names: chapters.map(\.name), starts: chapters.map(\.startSeconds), position: 0)[index].title
    }

    private func panel(close: @escaping @MainActor () -> Void) -> some View {
        ContentTabs(
            model: model.contentTabs(), selection: tab, onSelectTab: { tab = $0 },
            onSelectAudio: { model.selectAudio($0) },
            onSelectSubtitle: { model.selectSubtitle($0 == TrackRow.offID ? nil : $0) },
            onSelectChapter: { seconds in
                model.seek(to: seconds)
                close()
            },
            onClose: close
        )
    }

    @ViewBuilder private var status: some View {
        if let failure = model.failure {
            PlayerStatusView(.failed(title: String(localized: "Lecture impossible"), message: failure))
        } else if model.player == nil {
            PlayerStatusView(.failed(title: String(localized: "Lecture impossible"), message: String(localized: "Le lecteur n'est pas disponible.")))
        } else if model.phase == .loading || model.streamURL == nil {
            PlayerStatusView(.loading)
        } else if model.isSeeking {
            // An intentional jump: the press must be acknowledged at once, unlike a passive stall.
            PlayerStatusView(.loading)
        } else if model.isBuffering {
            // Short stalls (a seek) stay invisible: the spinner only fades in after 1.5 s.
            PlayerStatusView(.loading)
                .transition(.asymmetric(insertion: .opacity.animation(.easeIn(duration: 0.3).delay(1.5)), removal: .opacity))
        }
    }

    private var remoteHandlers: RemoteHandlers {
        RemoteHandlers(
            onTouch: { transport.reveal() },
            onSelect: { select() },
            onPlayPause: { transport.playPause() },
            onMenu: { if !transport.isScrubbing, model.dismissEndCard() { return }; if transport.menu() == .exit { onClose() } },
            onSkip: { transport.skip($0) },
            onDown: { transport.openPanel() },
            onPanBegan: { transport.panBegan() },
            onPan: { transport.pan(fraction: $0) },
            onPanEnded: {}
        )
    }

    // MARK: Trickplay, skip and next episode

    /// The trickplay tile under the scrub preview, to load; nil when not scrubbing or without trickplay.
    private var scrubTile: Int? {
        guard transport.isScrubbing, let sheet = model.trickplay else { return nil }
        return sheet.tile(at: transport.displayedPosition).tileIndex
    }

    private var scrubThumbnail: Image? {
        guard transport.isScrubbing, let sheet = model.trickplay else { return nil }
        return tiles.thumbnail(for: sheet, at: transport.displayedPosition)
    }

    private var skipLabel: String? {
        switch model.skippableSegment?.kind {
        case .intro: String(localized: "Passer l'intro")
        case .outro: String(localized: "Passer le générique")
        case nil: nil
        }
    }

    private var upNextCard: UpNextCardModel? {
        guard let card = model.endCard, let next = model.nextEpisode else { return nil }
        return UpNextCardModel(title: next.title, thumbnail: next.thumbnail, countdown: card.countdown, offersWatchCredits: card.phase == .credits)
    }

    /// Select acts on what the screen offers (next episode, skip) before it toggles pause; a scrub comes first.
    private func select() {
        guard !transport.isScrubbing else { return transport.select() }
        if let next = model.endCard != nil ? model.nextEpisode : nil {
            playNext(next)
        } else if model.skippableSegment != nil {
            model.skipSegment()
        } else {
            transport.select()
        }
    }

    /// Reports the current episode stopped, then hands over to the next one (Stopped goes out before its Start).
    private func playNext(_ next: NextEpisode) {
        model.stop()
        onPlayNext(next.target)
    }

    private func hideWhenIdle() async {
        guard let deadline = transport.visibility.deadline else { return }
        try? await Task.sleep(for: .seconds(max(deadline.timeIntervalSinceNow, 0)))
        guard !Task.isCancelled else { return }
        transport.expire()
    }

    private func clearSkipFeedback() async {
        guard let token = transport.skipFeedback?.token else { return }
        try? await Task.sleep(for: .milliseconds(900))
        guard !Task.isCancelled else { return }
        transport.clearSkipFeedback(token: token)
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "state: \(model.phase.rawValue)")
            Text(String(format: "time: %.1f / %.1f", model.timePosition, model.duration))
            Text(verbatim: "video-codec: \(model.videoCodec)")
            Text(verbatim: "hwdec-current: \(model.hwdecCurrent)")
            Text(verbatim: "trickplay: \(model.trickplay.map { "loaded (\($0.width) px)" } ?? "none")")
            Text(verbatim: "focus: \(focusProbe.description)")
            Text(verbatim: "panel presented: \(transport.isPanelOpen)")
            Text(verbatim: "osd visible: \(transport.visibility.isVisible)")
            Text(verbatim: "last press: \(lastPressRawValue.map(String.init) ?? "-")")
            if let error = model.lastError { Text(verbatim: "error: \(error)") }
        }
        .font(.system(size: 28, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .padding(24)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { RemoteInputUIView.debugPressSink = { lastPressRawValue = $0 } }
        .onDisappear { RemoteInputUIView.debugPressSink = nil }
    }
}

/// The panel's presentation: clear, so the video stays visible behind. It drops in from the top and, on close,
/// climbs back out the same way before the presentation is dismissed (invisibly: the content is already gone).
private struct PanelCover<Content: View>: View {
    let onDismiss: @MainActor () -> Void
    @ViewBuilder let content: (@escaping @MainActor () -> Void) -> Content
    @State private var slid = false
    @State private var closing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content(close)
            // Reduce Motion: the panel fades instead of travelling.
            .offset(y: slid || reduceMotion ? 0 : -700)
            .opacity(slid ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .presentationBackground(.clear)
            .onAppear { withAnimation(.easeOut(duration: 0.3)) { slid = true } }
    }

    private func close() {
        guard !closing else { return }
        closing = true
        withAnimation(.easeIn(duration: 0.3)) {
            slid = false
        } completion: {
            onDismiss()
        }
    }
}
