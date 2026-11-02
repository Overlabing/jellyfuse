import PlayerCore
import SwiftUI

/// Single V0 screen: plays the stream passed as launch argument `-url <stream url>`.
struct PlayerScreen: View {
    @State private var model = PlaybackModel()

    private static let streamURL = UserDefaults.standard.string(forKey: "url").flatMap(URL.init(string:))

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let player = model.player, let url = Self.streamURL {
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
    }

    private var message: String {
        if let failure = model.failure { return "Player failed: \(failure)" }
        return "Launch with -url <stream url> to play a stream."
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
