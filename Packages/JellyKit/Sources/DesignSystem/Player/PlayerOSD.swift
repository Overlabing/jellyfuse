import SwiftUI

/// The playback overlay at the bottom of the screen: title, progress bar with its playhead, elapsed time,
/// end time and remaining time over a dark gradient. Props in; the remote is read by `RemoteInputView`.
public struct PlayerOSD: View {
    @Environment(\.designMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let state: OSDState
    private let model: OSDModel
    private let scrubThumbnail: Image?

    /// `scrubThumbnail`: the frame under the playhead (trickplay), shown in the scrub bubble; nil = text only.
    public init(state: OSDState, model: OSDModel, scrubThumbnail: Image? = nil) {
        self.state = state
        self.model = model
        self.scrubThumbnail = scrubThumbnail
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.s) {
            if !state.isPanelOpen {
                Text("Balayez vers le bas pour plus d'informations", bundle: .module)
                    .font(Design.Typography.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, Design.Spacing.m)
                    .padding(.vertical, Design.Spacing.s)
                    .background(.black.opacity(0.35), in: Capsule())
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            }
            Spacer()
            Text(model.title)
                .font(Design.Typography.callout.weight(.bold))
                .lineLimit(1)
            OSDProgressBar(progress: model.progress, chapterMarks: model.chapterMarks, preview: model.preview, chapterTitle: model.chapterTitle, thumbnail: scrubThumbnail, skip: state.skip, isScrubbing: state.isScrubbing)
            times
        }
        .foregroundStyle(.white)
        .padding(.horizontal, metrics.screenMargin)
        .padding(.bottom, 100)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(alignment: .bottom) { gradient }
        .opacity(state.isVisible ? 1 : 0)
        .offset(y: state.isVisible || reduceMotion ? 0 : 24)
        .animation(.easeOut(duration: 0.25), value: state.isVisible)
        .accessibilityElement(children: .combine)
        // Faded out, the display is still in the tree: VoiceOver must not read it.
        .accessibilityHidden(!state.isVisible)
    }

    private var times: some View { OSDTimes(model: model) }

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

/// Elapsed time, end time and remaining time on one line.
struct OSDTimes: View {
    let model: OSDModel

    var body: some View {
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
}

/// The bar's dimensions: a 10-foot bar on tvOS, a finger-sized one on iOS.
struct OSDBarStyle: Equatable {
    var trackHeight: CGFloat
    var gap: Double
    var knob: CGFloat
    var knobScrubbing: CGFloat
    var bubbleWidth: CGFloat
    /// Space between the bar and the bubble above it.
    var bubbleLift: CGFloat
    var bubbleRadius: CGFloat

    static let tv = OSDBarStyle(trackHeight: 10, gap: 6, knob: 30, knobScrubbing: 44, bubbleWidth: 336, bubbleLift: 28, bubbleRadius: 20)
    /// The bubble stands well above the bar so the finger never covers it.
    static let touch = OSDBarStyle(trackHeight: 6, gap: 3, knob: 14, knobScrubbing: 24, bubbleWidth: 200, bubbleLift: 44, bubbleRadius: 14)
}

/// The track split into chapter segments (small gaps, like YouTube), the played part, the playhead, the scrub
/// preview and the skip chevrons. Without chapters it is one segment.
struct OSDProgressBar: View {
    let progress: Double
    let chapterMarks: [Double]
    let preview: String?
    let chapterTitle: String?
    let thumbnail: Image?
    let skip: SkipFeedback?
    let isScrubbing: Bool
    var style: OSDBarStyle = .tv
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var trackHeight: CGFloat { style.trackHeight }
    private var gap: Double { style.gap }
    private var knobSize: CGFloat { isScrubbing ? style.knobScrubbing : style.knob }

    var body: some View {
        GeometryReader { proxy in
            let segments = ChapterMarks.segments(marks: chapterMarks)
            let widths = ChapterMarks.segmentWidths(segments, width: proxy.size.width, gap: gap)
            let x = ChapterMarks.playheadX(progress: progress, segments: segments, width: proxy.size.width, gap: gap)
            ZStack(alignment: .leading) {
                HStack(spacing: gap) {
                    ForEach(segments.indices, id: \.self) { index in
                        let segment = segments[index]
                        let span = segment.upperBound - segment.lowerBound
                        let played = span > 0 ? min(max((progress - segment.lowerBound) / span, 0), 1) : 0
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.25))
                            Capsule().fill(.white).frame(width: widths[index] * played)
                        }
                        .frame(width: widths[index])
                    }
                }
                Circle()
                    .fill(.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.6), radius: 10, y: 6)
                    .position(x: x, y: proxy.size.height / 2)
                if let skip, preview == nil {
                    skipChevrons(skip).position(x: x, y: -44)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let preview {
                    // A box of known width centred on the playhead (kept on screen), standing on the bar:
                    // bottom-aligned to it, then lifted by the bar's height and a gap.
                    let centre = min(max(x, style.bubbleWidth / 2), proxy.size.width - style.bubbleWidth / 2)
                    bubble(preview, chapter: chapterTitle)
                        .offset(x: centre - style.bubbleWidth / 2, y: -(trackHeight + style.bubbleLift))
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: progress)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isScrubbing)
        }
        .frame(height: trackHeight)
        .accessibilityHidden(true)
    }

    /// The bubble's fixed width, with or without a thumbnail: nothing inside it can resize it or shift as frames,
    /// digits or chapter names change.
    /// One box (thumbnail, time, chapter) so a single offset places everything. Its content never animates
    /// by itself: the box eases to the playhead with the knob, and what is inside stays put in it.
    private func bubble(_ text: String, chapter: String?) -> some View {
        let inner = style.bubbleWidth - 2 * Design.Spacing.xs
        return VStack(spacing: 2) {
            if let thumbnail {
                thumbnail
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: inner)
                    // The overlay proposes the bar's 10 pt height: without this the frame collapses to it.
                    .fixedSize(horizontal: false, vertical: true)
                    .clipShape(RoundedRectangle(cornerRadius: style.bubbleRadius - 8))
                    .padding(.bottom, Design.Spacing.xs)
            }
            Text(text)
                .font(Design.Typography.callout.weight(.bold).monospacedDigit())
                .frame(width: inner)
            if let chapter {
                Text(chapter)
                    .font(Design.Typography.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .frame(width: inner)
            }
        }
        .multilineTextAlignment(.center)
        .padding(Design.Spacing.xs)
        .frame(width: style.bubbleWidth)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: style.bubbleRadius))
        .transaction { $0.animation = nil }
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
        .symbolEffect(.bounce, value: reduceMotion ? 0 : skip.token)
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
