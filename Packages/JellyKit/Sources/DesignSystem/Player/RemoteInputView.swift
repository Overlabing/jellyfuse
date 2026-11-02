#if os(tvOS)
import SwiftUI
import UIKit

/// What the Siri Remote does, as callbacks.
public struct RemoteHandlers {
    /// A finger rests on or moves over the pad.
    public var onTouch: @MainActor () -> Void
    /// Click of the pad centre.
    public var onSelect: @MainActor () -> Void
    public var onPlayPause: @MainActor () -> Void
    public var onMenu: @MainActor () -> Void
    /// Left / right click; repeats while held.
    public var onSkip: @MainActor (SkipDirection) -> Void
    /// Down click, or a downward swipe of the pad: the content panel.
    public var onDown: @MainActor () -> Void
    public var onPanBegan: @MainActor () -> Void
    /// Travel since `onPanBegan`, in pad widths.
    public var onPan: @MainActor (Double) -> Void
    public var onPanEnded: @MainActor () -> Void

    public init(
        onTouch: @escaping @MainActor () -> Void, onSelect: @escaping @MainActor () -> Void,
        onPlayPause: @escaping @MainActor () -> Void, onMenu: @escaping @MainActor () -> Void,
        onSkip: @escaping @MainActor (SkipDirection) -> Void, onDown: @escaping @MainActor () -> Void,
        onPanBegan: @escaping @MainActor () -> Void,
        onPan: @escaping @MainActor (Double) -> Void, onPanEnded: @escaping @MainActor () -> Void
    ) {
        self.onTouch = onTouch
        self.onSelect = onSelect
        self.onPlayPause = onPlayPause
        self.onMenu = onMenu
        self.onSkip = onSkip
        self.onDown = onDown
        self.onPanBegan = onPanBegan
        self.onPan = onPan
        self.onPanEnded = onPanEnded
    }
}

/// UIKit bridge for the Siri Remote. SwiftUI cannot tell a pad swipe from a pad click (both are
/// `onMoveCommand`) and does not expose the continuous swipe, which scrubbing needs. This view is the only
/// focusable thing of the player; it reads:
/// - presses (`UIPress`): arrows = pad edge clicks, select, play/pause, hold-to-repeat on the arrows;
/// - a pan recognizer restricted to indirect touches (the pad): the swipe;
/// - Menu, handled here and not passed up the responder chain, so the system does not also dismiss the player.
public struct RemoteInputView: UIViewControllerRepresentable {
    private let handlers: RemoteHandlers
    private let isActive: Bool

    /// `isActive` false hands the focus to the SwiftUI surface shown over the player (the content panel);
    /// true takes it back. Presses reach this view only while it is the focused one.
    public init(handlers: RemoteHandlers, isActive: Bool = true) {
        self.handlers = handlers
        self.isActive = isActive
    }

    public func makeUIViewController(context: Context) -> RemoteInputViewController {
        let controller = RemoteInputViewController()
        controller.remoteView.handlers = handlers
        controller.remoteView.takesFocus = isActive
        return controller
    }

    public func updateUIViewController(_ uiViewController: RemoteInputViewController, context: Context) {
        uiViewController.remoteView.handlers = handlers
        uiViewController.setActive(isActive)
    }
}

/// A bare `UIView` in a SwiftUI `.background` is never offered to the focus engine. A view controller that
/// names the input view as its preferred focus environment is, and it asks for the focus once on screen.
public final class RemoteInputViewController: UIViewController {
    let remoteView = RemoteInputUIView()

    public override func loadView() { view = remoteView }

    /// Nothing to prefer while a SwiftUI surface holds the focus: the engine then takes the only focusable
    /// thing left (the panel) by itself.
    public override var preferredFocusEnvironments: [any UIFocusEnvironment] {
        remoteView.takesFocus ? [remoteView] : []
    }

    /// Gives the focus up (`false`) or takes it back (`true`). Giving up makes the bridge strictly invisible to
    /// the focus engine (hidden: not focusable, not hit-testable, not an occluder), so the engine moves the
    /// focus to the panel on its own. The update request is on this controller, which contains the focused
    /// item: it is the one environment whose request is always honoured. Next turn, once SwiftUI has applied
    /// the panel's insertion or removal.
    func setActive(_ active: Bool) {
        guard remoteView.takesFocus != active else { return }
        remoteView.takesFocus = active
        DispatchQueue.main.async { [weak self] in
            self?.setNeedsFocusUpdate()
            self?.updateFocusIfNeeded()
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }
}

public final class RemoteInputUIView: UIView {
    /// Delay before a held arrow starts repeating, then the delay between repeats.
    private static let repeatDelay: Duration = .milliseconds(500)
    private static let repeatInterval: Duration = .milliseconds(300)

    /// The tvOS simulator's Menu / Back key arrives as this private press type instead of `.menu`, and the
    /// system would then dismiss the player: it is handled like Menu.
    static let simulatorMenu = UIPress.PressType(rawValue: 2041)!
    /// A press delivered both ways must not count twice.
    private static let menuDebounce: TimeInterval = 0.3
    /// Downward travel, in pad heights, that counts as a swipe down.
    private static let downSwipe: CGFloat = 0.2

    /// Diagnostic tap (`-stats`): raw type of every press that reaches the bridge.
    public static var debugPressSink: (@MainActor (Int) -> Void)?

    var handlers: RemoteHandlers?
    /// False while a SwiftUI surface (the content panel) must hold the focus.
    var takesFocus = true {
        didSet {
            isHidden = !takesFocus
            isUserInteractionEnabled = takesFocus
            if !takesFocus { stopRepeating() }
        }
    }
    private var panTriggeredDown = false
    private var lastMenu = Date.distantPast
    private var repeatTask: Task<Void, Never>?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        // The system's presentation-dismissal recognizer sees Menu BEFORE responder presses: only a
        // recognizer of our own wins that race on hardware. It must keep its default allowedTouchTypes
        // (emptying them kills press delivery); cancelsTouchesInView = false alone protects pad navigation.
        let menu = UITapGestureRecognizer(target: self, action: #selector(menuPressed))
        menu.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        menu.cancelsTouchesInView = false
        addGestureRecognizer(menu)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panChanged(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        // The pad touch must also reach touchesBegan, which reveals the display before any movement.
        pan.cancelsTouchesInView = false
        addGestureRecognizer(pan)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var canBecomeFocused: Bool { takesFocus }

    // VoiceOver: this view is the player's only focus target. Direct interaction hands the raw presses
    // (arrows, select, play/pause) to it instead of VoiceOver's own navigation.
    public override var isAccessibilityElement: Bool {
        get { takesFocus }
        set {}
    }
    public override var accessibilityLabel: String? {
        get { String(localized: "Lecteur vidéo", bundle: .module) }
        set {}
    }
    public override var accessibilityTraits: UIAccessibilityTraits {
        get { .allowsDirectInteraction }
        set {}
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopRepeating() }
    }

    // MARK: Pad touch

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if touches.contains(where: { $0.type == .indirect }) { handlers?.onTouch() }
    }

    @objc private func menuPressed() { fireMenu() }

    private func fireMenu() {
        guard Date.now.timeIntervalSince(lastMenu) > Self.menuDebounce else { return }
        lastMenu = .now
        handlers?.onMenu()
    }

    @objc private func panChanged(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            panTriggeredDown = false
            handlers?.onPanBegan()
        case .changed:
            let travel = recognizer.translation(in: self)
            // A mostly vertical swipe down, once per gesture: the content panel (like the system player).
            if !panTriggeredDown, travel.y / max(bounds.height, 1) > Self.downSwipe, travel.y > 2 * abs(travel.x) {
                panTriggeredDown = true
                handlers?.onDown()
            }
            handlers?.onPan(travel.x / max(bounds.width, 1))
        case .ended, .cancelled, .failed:
            handlers?.onPanEnded()
        default:
            break
        }
    }

    // MARK: Presses

    public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = presses
        for press in presses {
            switch press.type {
            case .leftArrow: startRepeating(.backward)
            case .rightArrow: startRepeating(.forward)
            case .select, .playPause, .downArrow: break
            // The real remote's Menu, consumed here so the system never suspends the app; the recognizer
            // route died on hardware once it stopped listening to touches.
            case .menu, Self.simulatorMenu: break
            default: continue
            }
            unhandled.remove(press)
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }

    public override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if let sink = Self.debugPressSink, let press = presses.first { sink(press.type.rawValue) }
        var unhandled = presses
        for press in presses {
            switch press.type {
            case .leftArrow, .rightArrow: stopRepeating()
            case .downArrow: handlers?.onDown()
            case .select: handlers?.onSelect()
            case .playPause: handlers?.onPlayPause()
            case .menu, Self.simulatorMenu: fireMenu()
            default: continue
            }
            unhandled.remove(press)
        }
        if !unhandled.isEmpty { super.pressesEnded(unhandled, with: event) }
    }

    public override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        stopRepeating()
        super.pressesCancelled(presses, with: event)
    }

    /// Skips once at once, then again every `repeatInterval` after `repeatDelay` while the arrow is held.
    private func startRepeating(_ direction: SkipDirection) {
        stopRepeating()
        handlers?.onSkip(direction)
        repeatTask = Task { [weak self] in
            try? await Task.sleep(for: Self.repeatDelay)
            while !Task.isCancelled {
                self?.handlers?.onSkip(direction)
                try? await Task.sleep(for: Self.repeatInterval)
            }
        }
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}

/// Where the focus is, for the `-stats` overlay: the class of the focused item and whether it is the remote
/// bridge or something else (the content panel, a presentation) (nothing focused = the pad does nothing).
@MainActor @Observable
public final class FocusProbe {
    public private(set) var description = "none"
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    public init() {
        observer = NotificationCenter.default.addObserver(forName: UIFocusSystem.didUpdateNotification, object: nil, queue: .main) { [weak self] note in
            // Delivered on the main queue; the notification is only read here.
            nonisolated(unsafe) let note = note
            MainActor.assumeIsolated {
                let item = (note.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext)?.nextFocusedItem
                self?.description = Self.describe(item)
            }
        }
    }

    isolated deinit { observer.map(NotificationCenter.default.removeObserver) }

    private static func describe(_ item: (any UIFocusItem)?) -> String {
        guard let item else { return "none" }
        var environment: (any UIFocusEnvironment)? = item
        while let current = environment {
            if current is RemoteInputUIView { return "bridge (\(type(of: item)))" }
            environment = current.parentFocusEnvironment
        }
        return "other (\(type(of: item)))"
    }
}
#endif
