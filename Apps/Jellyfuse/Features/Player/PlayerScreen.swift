import DesignSystem
import HomePresentation
import PlayerCore
import PlayerPresentation
import SwiftUI

/// Plays one item, reporting it to the server. The Siri Remote drives the transport (see `RemoteInputView`);
/// Menu closes the display, then the player.
struct PlayerScreen: View {
    let onClose: () -> Void
    @State private var model: PlaybackModel
    @State private var transport: TransportController
    @State private var tab = PlayerTab.info
    /// The panel stays mounted while it slides out: the UIKit-hosted panel has no SwiftUI removal transition,
    /// so both directions are an explicit offset animation.
    @State private var panelMounted = false
    @State private var panelSlid = false
    /// Bumped once the panel is on screen, which is when it can take the focus.
    @State private var panelFocusToken = 0
    /// Debug overlay: launch with `-stats YES`.
    private let showsStats = UserDefaults.standard.bool(forKey: "stats")
    @State private var focusProbe = FocusProbe()

    init(target: PlayTarget, services: PlaybackServices, onClose: @escaping () -> Void) {
        self.onClose = onClose
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
            PlayerOSD(state: transport.state, model: osdModel)
                .ignoresSafeArea()
            if panelMounted { panel }
            status
            if showsStats { stats }
        }
        .animation(.easeOut(duration: 0.2), value: model.isBuffering)
        .onChange(of: transport.isPanelOpen) { _, open in setPanel(open) }
        // While the panel is open it owns the focus (it is a SwiftUI surface); the bridge takes it back on close.
        .overlay { RemoteInputView(handlers: remoteHandlers, isActive: !transport.isPanelOpen).ignoresSafeArea() }
        .task(id: transport.visibility.deadline) { await hideWhenIdle() }
        .task(id: transport.skipFeedback?.token) { await clearSkipFeedback() }
        .onChange(of: model.isPaused) { _, paused in transport.pausedChanged(paused) }
        .onChange(of: model.phase) { _, phase in if phase == .ended { onClose() } }
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

    private static let panelTravel: CGFloat = 700

    /// Down from the top on open, back up on close, the same 0.3 s each way.
    private func setPanel(_ open: Bool) {
        if open {
            panelMounted = true
            // Next turn, so the first frame is drawn off screen and the move animates.
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.3)) {
                    panelSlid = true
                } completion: {
                    if transport.isPanelOpen { panelFocusToken += 1 }
                }
            }
        } else {
            withAnimation(.easeIn(duration: 0.3)) {
                panelSlid = false
            } completion: {
                if !transport.isPanelOpen { panelMounted = false }
            }
        }
    }

    /// The chapter under the playhead (or the scrub preview), for the scrub bubble.
    private var chapterTitle: String? {
        let chapters = model.chapters
        guard let index = ChapterMarks.currentIndex(starts: chapters.map(\.startSeconds), position: transport.displayedPosition) else { return nil }
        return ChapterRow.rows(names: chapters.map(\.name), starts: chapters.map(\.startSeconds), position: 0)[index].title
    }

    private var panel: some View {
        ContentTabs(
            model: model.contentTabs(), selection: tab, onSelectTab: { tab = $0 },
            onSelectAudio: { model.selectAudio($0) },
            onSelectSubtitle: { model.selectSubtitle($0 == TrackRow.offID ? nil : $0) },
            onSelectChapter: { seconds in
                model.seek(to: seconds)
                transport.closePanel()
            },
            onClose: { transport.closePanel() },
            focusToken: panelFocusToken
        )
        .offset(y: panelSlid ? 0 : -Self.panelTravel)
        .opacity(panelSlid ? 1 : 0)
        // Sliding out: no longer a focus target, the bridge already has the focus back.
        .disabled(!transport.isPanelOpen)
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
            onSelect: { transport.select() },
            onPlayPause: { transport.playPause() },
            onMenu: { if transport.menu() == .exit { onClose() } },
            onSkip: { transport.skip($0) },
            onDown: { transport.openPanel() },
            onPanBegan: { transport.panBegan() },
            onPan: { transport.pan(fraction: $0) },
            onPanEnded: {}
        )
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
            Text("state: \(model.phase.rawValue)")
            Text(String(format: "time: %.1f / %.1f", model.timePosition, model.duration))
            Text("video-codec: \(model.videoCodec)")
            Text("hwdec-current: \(model.hwdecCurrent)")
            Text("focus: \(focusProbe.description)")
            Text("panel open: \(transport.isPanelOpen)")
            if let error = model.lastError { Text("error: \(error)") }
        }
        .font(.system(size: 28, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .padding(24)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
