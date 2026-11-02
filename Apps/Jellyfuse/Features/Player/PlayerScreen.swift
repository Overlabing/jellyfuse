import HomePresentation
import PlayerCore
import SwiftUI

/// Plays one item, reporting it to the server. Menu closes it.
struct PlayerScreen: View {
    let onClose: () -> Void
    @State private var model: PlaybackModel

    init(target: PlayTarget, services: PlaybackServices, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _model = State(initialValue: PlaybackModel(target: target, services: services))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let player = model.player, let url = model.streamURL {
                MpvPlayerView(player: player, startURL: url)
                    .ignoresSafeArea()
                stats
            } else {
                Text(message)
                    .font(.title2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .focusable()
        .onPlayPauseCommand { model.togglePause() }
        .onExitCommand(perform: onClose)
        .onDisappear { model.stop() }
    }

    private var message: String {
        if let failure = model.failure { return "Player failed: \(failure)" }
        return model.player == nil ? "Player unavailable." : "Loading…"
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("state: \(model.state)")
            Text(String(format: "time: %.1f / %.1f", model.timePosition, model.duration))
            Text("video-codec: \(model.videoCodec)")
            Text("hwdec-current: \(model.hwdecCurrent)")
            if let error = model.lastError { Text("error: \(error)") }
        }
        .font(.system(size: 28, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .padding(24)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .padding(60)
    }
}
