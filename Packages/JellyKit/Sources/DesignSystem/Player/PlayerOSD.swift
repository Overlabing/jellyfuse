import SwiftUI

/// The playback overlay at the bottom of the screen: title, progress bar with its playhead, elapsed time,
/// end time and remaining time over a dark gradient. Props in; the remote is read by `RemoteInputView`.
public struct PlayerOSD: View {
    @Environment(\.designMetrics) private var metrics
    private let state: OSDState
    private let model: OSDModel

    public init(state: OSDState, model: OSDModel) {
        self.state = state
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.s) {
            Spacer()
            Text(model.title)
                .font(Design.Typography.callout.weight(.bold))
                .lineLimit(1)
            OSDProgressBar(progress: model.progress, preview: model.preview, skip: state.skip, isScrubbing: state.isScrubbing)
            times
        }
        .foregroundStyle(.white)
        .padding(.horizontal, metrics.screenMargin)
        .padding(.bottom, 100)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(alignment: .bottom) { gradient }
        .opacity(state.isVisible ? 1 : 0)
        .offset(y: state.isVisible ? 0 : 24)
        .animation(.easeOut(duration: 0.25), value: state.isVisible)
        .accessibilityElement(children: .combine)
    }

    private var times: some View {
        HStack {
            Text(model.elapsed)
            Spacer()
            if let endsAt = model.endsAt {
                Text(endsAt).foregroundStyle(Design.Palette.textSecondary)
            }
            Spacer()
            Text(model.remaining ?? "")
        }
        .font(Design.Typography.caption.monospacedDigit())
        .foregroundStyle(.white.opacity(0.85))
    }

    /// Legibility over any frame (mockup `.osd-bot`): black .85 at the edge, .5 at 55%, clear at the top.
    private var gradient: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0), location: 0),
                .init(color: .black.opacity(0.5), location: 0.45),
                .init(color: .black.opacity(0.85), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: 480)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }
}

/// The track, the played part, the playhead, the scrub preview and the skip chevrons.
struct OSDProgressBar: View {
    let progress: Double
    let preview: String?
    let skip: SkipFeedback?
    let isScrubbing: Bool

    private let trackHeight: CGFloat = 10
    private var knobSize: CGFloat { isScrubbing ? 44 : 30 }

    var body: some View {
        GeometryReader { proxy in
            let x = proxy.size.width * min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(.white).frame(width: x)
                Circle()
                    .fill(.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.6), radius: 10, y: 6)
                    .position(x: x, y: proxy.size.height / 2)
                if let preview {
                    bubble(preview).position(x: x, y: -44)
                } else if let skip {
                    skipChevrons(skip).position(x: x, y: -44)
                }
            }
            .animation(.easeOut(duration: 0.15), value: progress)
            .animation(.easeOut(duration: 0.15), value: isScrubbing)
        }
        .frame(height: trackHeight)
        .accessibilityHidden(true)
    }

    private func bubble(_ text: String) -> some View {
        Text(text)
            .font(Design.Typography.callout.weight(.bold).monospacedDigit())
            .padding(.horizontal, Design.Spacing.s)
            .padding(.vertical, Design.Spacing.xs)
            .background(.black.opacity(0.6), in: Capsule())
    }

    private func skipChevrons(_ skip: SkipFeedback) -> some View {
        HStack(spacing: 6) {
            if skip.direction == .backward { Image(systemName: "chevron.left.2") }
            Text("10 s").font(Design.Typography.callout.weight(.bold).monospacedDigit())
            if skip.direction == .forward { Image(systemName: "chevron.right.2") }
        }
        .padding(.horizontal, Design.Spacing.s)
        .padding(.vertical, Design.Spacing.xs)
        .background(.black.opacity(0.6), in: Capsule())
        .symbolEffect(.bounce, value: skip.token)
        .id(skip.token)
        .transition(.opacity)
    }
}

#if DEBUG
#Preview("OSD") {
    ZStack {
        LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
        PlayerOSD(
            state: OSDState(isVisible: true, isPaused: true),
            model: OSDModel(title: "Fréquences › S2E5 · Fréquence zéro", position: 1164, duration: 2760)
        )
    }
    .ignoresSafeArea()
}
#endif
