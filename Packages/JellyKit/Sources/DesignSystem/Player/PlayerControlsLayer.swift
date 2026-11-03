import SwiftUI

/// What the player's controls ask of the screen. On iOS the touch layer owns the close button and the panel's
/// selections; on tvOS the remote bridge and the screen's own cover do, and these callbacks are unused.
public struct PlayerControlsHandlers: Sendable {
    /// The close (X) button: leave the player.
    public var onClose: @MainActor () -> Void
    /// A Jellyfin stream index.
    public var onSelectAudio: @MainActor (Int) -> Void
    /// A Jellyfin stream index, or `TrackRow.offID`.
    public var onSelectSubtitle: @MainActor (Int) -> Void
    /// Start of the chapter, in seconds. The panel closes after it.
    public var onSelectChapter: @MainActor (Double) -> Void

    public init(
        onClose: @escaping @MainActor () -> Void, onSelectAudio: @escaping @MainActor (Int) -> Void,
        onSelectSubtitle: @escaping @MainActor (Int) -> Void, onSelectChapter: @escaping @MainActor (Double) -> Void
    ) {
        self.onClose = onClose
        self.onSelectAudio = onSelectAudio
        self.onSelectSubtitle = onSelectSubtitle
        self.onSelectChapter = onSelectChapter
    }
}

/// The player's controls on top of the video, per platform: on tvOS the OSD (the remote is read by
/// `RemoteInputView`, the panel is the screen's cover); on iOS / iPadOS the touch layer (taps, double-taps,
/// scrubbable bar, buttons, panel as a sheet). Both are driven by the same `TransportController`.
///
/// The screen rebuilds `model` from `transport.displayedPosition` (and `transport.isScrubbing`) so the bar follows
/// the finger while scrubbing.
public struct PlayerControlsLayer: View {
    private let transport: TransportController
    private let model: OSDModel
    private let scrubThumbnail: Image?
    private let panel: ContentTabsModel?
    private let handlers: PlayerControlsHandlers

    /// `scrubThumbnail`: the trickplay frame under the playhead. `panel`: nil hides the track / chapter buttons.
    public init(
        transport: TransportController, model: OSDModel, scrubThumbnail: Image? = nil, panel: ContentTabsModel? = nil,
        handlers: PlayerControlsHandlers
    ) {
        self.transport = transport
        self.model = model
        self.scrubThumbnail = scrubThumbnail
        self.panel = panel
        self.handlers = handlers
    }

    public var body: some View {
        #if os(iOS)
        TouchPlayerControls(transport: transport, model: model, scrubThumbnail: scrubThumbnail, panel: panel, handlers: handlers)
        #else
        PlayerOSD(state: transport.state, model: model, scrubThumbnail: scrubThumbnail)
        #endif
    }
}
