#if os(iOS)
import SwiftUI

/// The touch controls of the player (iPhone / iPad), in the Infuse / Apple TV app mould:
/// - tap on the video: shows / hides the controls (they hide by themselves 4 s after the last touch while playing);
/// - double-tap on the left / right half: -10 s / +10 s, with a flash on that side;
/// - centre buttons: -10 s, play / pause, +10 s; close button, title, audio-subtitles and chapters buttons on top;
/// - bottom bar: dragging anywhere on it scrubs (bubble with the time, the chapter and the trickplay frame above
///   the finger); the seek happens when the finger lifts.
/// Props in; the transport (`TransportController`) holds all the state and logic.
struct TouchPlayerControls: View {
    let transport: TransportController
    let model: OSDModel
    let scrubThumbnail: Image?
    let panel: ContentTabsModel?
    let handlers: PlayerControlsHandlers

    @State private var panelTab: PlayerTab = .info
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isVisible: Bool { transport.visibility.isVisible }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                gestureLayer(width: proxy.size.width)
                skipFlash(width: proxy.size.width)
                chrome
                    .opacity(isVisible ? 1 : 0)
                    .allowsHitTesting(isVisible)
                    .accessibilityHidden(!isVisible)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: isVisible)
        }
        .foregroundStyle(.white)
        .sheet(isPresented: panelBinding) { sheet }
        .task(id: transport.visibility.deadline) {
            guard let deadline = transport.visibility.deadline else { return }
            try? await Task.sleep(for: .seconds(max(deadline.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled else { return }
            transport.expire()
        }
        .task(id: transport.skipFeedback?.token) {
            guard let token = transport.skipFeedback?.token else { return }
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled else { return }
            transport.clearSkipFeedback(token: token)
        }
    }

    // MARK: Gestures on the video

    /// A double-tap is tried first, so a single tap waits a beat: the price of having both on the same surface.
    private func gestureLayer(width: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(count: 2)
                    .onEnded { tap in
                        transport.skip(TouchMath.skipDirection(tapX: tap.location.x, width: width), revealsDisplay: false)
                    }
                    .exclusively(before: SpatialTapGesture().onEnded { _ in transport.toggleDisplay() })
            )
            .accessibilityHidden(true)
    }

    /// The ±10 s flash, on the side that was tapped; it shows even when the controls are hidden.
    private func skipFlash(width: CGFloat) -> some View {
        ZStack {
            if let skip = transport.skipFeedback {
                HStack(spacing: 6) {
                    if skip.direction == .backward { Image(systemName: "chevron.left.2") }
                    Text("10 s").monospacedDigit()
                    if skip.direction == .forward { Image(systemName: "chevron.right.2") }
                }
                .font(.title3.weight(.bold))
                .padding(.horizontal, Design.Spacing.m)
                .padding(.vertical, Design.Spacing.s)
                .background(.black.opacity(0.55), in: Capsule())
                .symbolEffect(.bounce, value: reduceMotion ? 0 : skip.token)
                .id(skip.token)
                .transition(.opacity)
                .offset(x: skip.direction == .backward ? -width * 0.25 : width * 0.25)
            }
        }
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: transport.skipFeedback)
    }

    // MARK: Controls

    private var chrome: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                bottomBar
            }
            .padding(.horizontal, Design.Spacing.m)
            .padding(.vertical, Design.Spacing.s)
            .background { gradients }
            centreControls
                .opacity(transport.isScrubbing ? 0 : 1)
                .allowsHitTesting(!transport.isScrubbing)
        }
    }

    private var topBar: some View {
        HStack(spacing: Design.Spacing.s) {
            roundButton("xmark", label: Text("Fermer", tableName: "PlayerTouch", bundle: .module)) { handlers.onClose() }
            Text(model.title)
                .font(Design.Typography.callout.weight(.bold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let panel {
                if !panel.audio.isEmpty || !panel.subtitles.isEmpty {
                    roundButton("captions.bubble", label: Text("Audio et sous-titres", tableName: "PlayerTouch", bundle: .module)) {
                        open(panel.audio.isEmpty ? .subtitles : .audio)
                    }
                }
                if !panel.chapters.isEmpty {
                    roundButton("list.bullet", label: Text(verbatim: PlayerTab.chapters.title)) { open(.chapters) }
                }
            }
        }
    }

    private var centreControls: some View {
        HStack(spacing: 56) {
            Button { transport.skip(.backward) } label: {
                Image(systemName: "gobackward.10").font(.system(size: 36))
            }
            .accessibilityLabel(Text("Reculer de 10 secondes", tableName: "PlayerTouch", bundle: .module))
            Button { transport.playPause() } label: {
                Image(systemName: transport.state.isPaused ? "play.fill" : "pause.fill").font(.system(size: 52))
                    .frame(width: 72, height: 72)
            }
            .accessibilityLabel(transport.state.isPaused ? Text("Lecture", tableName: "PlayerTouch", bundle: .module) : Text("Pause", tableName: "PlayerTouch", bundle: .module))
            Button { transport.skip(.forward) } label: {
                Image(systemName: "goforward.10").font(.system(size: 36))
            }
            .accessibilityLabel(Text("Avancer de 10 secondes", tableName: "PlayerTouch", bundle: .module))
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.5), radius: 8)
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            ScrubBar(transport: transport, model: model, thumbnail: scrubThumbnail)
            OSDTimes(model: model)
        }
    }

    private func roundButton(_ symbol: String, label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.35), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Legibility over any frame: black at the top and bottom edges, clear in the middle.
    private var gradients: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0.7), .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 140)
            Spacer(minLength: 0)
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom).frame(height: 200)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Panel as a sheet

    private func open(_ tab: PlayerTab) {
        panelTab = tab
        transport.openPanel()
    }

    private var panelBinding: Binding<Bool> {
        Binding(
            get: { transport.isPanelOpen && panel != nil },
            set: { if !$0 { transport.closePanel() } }
        )
    }

    @ViewBuilder private var sheet: some View {
        if let panel {
            ContentTabs(
                model: panel, selection: panelTab, onSelectTab: { panelTab = $0 },
                onSelectAudio: { handlers.onSelectAudio($0) }, onSelectSubtitle: { handlers.onSelectSubtitle($0) },
                onSelectChapter: { start in
                    handlers.onSelectChapter(start)
                    transport.closePanel()
                },
                onClose: { transport.closePanel() }, presentation: .sheet
            )
            .padding(.top, Design.Spacing.m)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.regularMaterial)
            .preferredColorScheme(.dark)
        }
    }
}

/// The progress bar with a finger-sized touch area: dragging on it scrubs, a tap seeks there.
struct ScrubBar: View {
    let transport: TransportController
    let model: OSDModel
    let thumbnail: Image?

    private let style = OSDBarStyle.touch
    private let touchHeight: CGFloat = 44

    var body: some View {
        GeometryReader { proxy in
            OSDProgressBar(
                progress: model.progress, chapterMarks: model.chapterMarks, preview: model.preview, chapterTitle: model.chapterTitle,
                thumbnail: thumbnail, skip: nil, isScrubbing: transport.isScrubbing, style: style
            )
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        transport.touchScrub(fraction: Self.fraction(atX: drag.location.x, width: proxy.size.width, marks: model.chapterMarks, gap: style.gap))
                    }
                    .onEnded { _ in transport.touchScrubEnded() }
            )
        }
        .frame(height: touchHeight)
        .accessibilityElement()
        .accessibilityLabel(Text("Progression", tableName: "PlayerTouch", bundle: .module))
        .accessibilityValue(model.elapsed)
        .accessibilityAdjustableAction { direction in
            transport.skip(direction == .increment ? .forward : .backward)
        }
    }

    /// The file fraction under a touch, honouring the gaps between chapter segments.
    static func fraction(atX x: Double, width: Double, marks: [Double], gap: Double) -> Double {
        ChapterMarks.progress(atX: x, segments: ChapterMarks.segments(marks: marks), width: width, gap: gap)
    }
}

#if DEBUG
enum TouchPreviewFixtures {
    @MainActor final class Player {
        var position = 1164.0
        var duration = 2760.0
        var isPaused = false

        func controller() -> TransportController {
            TransportController(driver: .init(
                position: { self.position }, duration: { self.duration }, isPaused: { self.isPaused },
                seek: { self.position = $0 }, setPaused: { self.isPaused = $0 }
            ))
        }
    }

    static let panel = ContentTabsModel(
        info: InfoContent(title: "Fréquences › S2E5", facts: "2021 · 46 min · Science-fiction", synopsis: "Une onde étrange traverse la ville."),
        audio: [TrackRow(id: 1, title: "Français · EAC3 5.1", detail: "Par défaut", isSelected: true), TrackRow(id: 2, title: "English · AAC 2.0", isSelected: false)],
        subtitles: [TrackRow(id: 3, title: "Français", detail: "SRT", isSelected: false)],
        chapters: ChapterRow.rows(names: ["Générique", nil, "Révélation", nil], starts: [0, 600, 1500, 2300], position: 1164),
        canSwitchTracks: true
    )

    static let handlers = PlayerControlsHandlers(onClose: {}, onSelectAudio: { _ in }, onSelectSubtitle: { _ in }, onSelectChapter: { _ in })

    static var thumbnail: Image {
        let size = CGSize(width: 320, height: 180)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return Image(uiImage: image)
    }

    @MainActor static func layer(
        paused: Bool = false, visible: Bool = true, scrubAt: Double? = nil, chapters: Bool = true, panelOpen: Bool = false
    ) -> some View {
        let player = Player()
        player.isPaused = paused
        let transport = player.controller()
        if visible { transport.reveal() }
        if panelOpen { transport.openPanel() }
        if let scrubAt { transport.touchScrub(fraction: scrubAt) }
        let marks = chapters ? ChapterMarks.fractions(starts: [0, 600, 1500, 2300], duration: player.duration) : []
        let model = OSDModel(
            title: "Fréquences › S2E5 · Fréquence zéro", position: transport.displayedPosition, duration: player.duration,
            isScrubbing: transport.isScrubbing, chapterMarks: marks, chapterTitle: scrubAt == nil ? nil : "Révélation"
        )
        return ZStack {
            LinearGradient(colors: [.indigo, .black, .orange.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            PlayerControlsLayer(
                transport: transport, model: model, scrubThumbnail: scrubAt == nil ? nil : thumbnail,
                panel: chapters ? panel : ContentTabsModel(info: panel.info, audio: panel.audio, subtitles: panel.subtitles, chapters: [], canSwitchTracks: true),
                handlers: handlers
            )
        }
    }
}

#Preview("Lecture", traits: .landscapeLeft) { TouchPreviewFixtures.layer() }
#Preview("Pause", traits: .landscapeLeft) { TouchPreviewFixtures.layer(paused: true) }
#Preview("Scrub", traits: .landscapeLeft) { TouchPreviewFixtures.layer(paused: true, scrubAt: 0.55) }
#Preview("Sans chapitres", traits: .landscapeLeft) { TouchPreviewFixtures.layer(chapters: false) }
#Preview("Panneau", traits: .landscapeLeft) { TouchPreviewFixtures.layer(paused: true, panelOpen: true) }
#endif
#endif
