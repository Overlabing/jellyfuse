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
    public var onPanBegan: @MainActor () -> Void
    /// Travel since `onPanBegan`, in pad widths.
    public var onPan: @MainActor (Double) -> Void
    public var onPanEnded: @MainActor () -> Void

    public init(
        onTouch: @escaping @MainActor () -> Void, onSelect: @escaping @MainActor () -> Void,
        onPlayPause: @escaping @MainActor () -> Void, onMenu: @escaping @MainActor () -> Void,
        onSkip: @escaping @MainActor (SkipDirection) -> Void, onPanBegan: @escaping @MainActor () -> Void,
        onPan: @escaping @MainActor (Double) -> Void, onPanEnded: @escaping @MainActor () -> Void
    ) {
        self.onTouch = onTouch
        self.onSelect = onSelect
        self.onPlayPause = onPlayPause
        self.onMenu = onMenu
        self.onSkip = onSkip
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
/// - a Menu press recognizer, which keeps the system from dismissing the player behind our back.
public struct RemoteInputView: UIViewRepresentable {
    private let handlers: RemoteHandlers

    public init(handlers: RemoteHandlers) { self.handlers = handlers }

    public func makeUIView(context: Context) -> RemoteInputUIView {
        let view = RemoteInputUIView()
        view.handlers = handlers
        return view
    }

    public func updateUIView(_ uiView: RemoteInputUIView, context: Context) {
        uiView.handlers = handlers
    }
}

public final class RemoteInputUIView: UIView {
    /// Delay before a held arrow starts repeating, then the delay between repeats.
    private static let repeatDelay: Duration = .milliseconds(500)
    private static let repeatInterval: Duration = .milliseconds(300)

    var handlers: RemoteHandlers?
    private var repeatTask: Task<Void, Never>?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        let menu = UITapGestureRecognizer(target: self, action: #selector(menuPressed))
        menu.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        addGestureRecognizer(menu)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panChanged(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        // The pad touch must also reach touchesBegan, which reveals the display before any movement.
        pan.cancelsTouchesInView = false
        addGestureRecognizer(pan)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var canBecomeFocused: Bool { true }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopRepeating()
        } else {
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
        }
    }

    // MARK: Pad touch

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if touches.contains(where: { $0.type == .indirect }) { handlers?.onTouch() }
    }

    @objc private func panChanged(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            handlers?.onPanBegan()
        case .changed:
            handlers?.onPan(recognizer.translation(in: self).x / max(bounds.width, 1))
        case .ended, .cancelled, .failed:
            handlers?.onPanEnded()
        default:
            break
        }
    }

    @objc private func menuPressed() { handlers?.onMenu() }

    // MARK: Presses

    public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = presses
        for press in presses {
            switch press.type {
            case .leftArrow: startRepeating(.backward)
            case .rightArrow: startRepeating(.forward)
            case .select, .playPause: break
            default: continue
            }
            unhandled.remove(press)
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }

    public override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = presses
        for press in presses {
            switch press.type {
            case .leftArrow, .rightArrow: stopRepeating()
            case .select: handlers?.onSelect()
            case .playPause: handlers?.onPlayPause()
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
#endif
