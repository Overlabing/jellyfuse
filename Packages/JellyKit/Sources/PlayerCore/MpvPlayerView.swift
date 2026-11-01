import SwiftUI
import UIKit

/// Hosts the player's video surface. Optionally starts playing `startURL` once the surface is installed.
public struct MpvPlayerView: UIViewControllerRepresentable {
    private let player: MpvPlayer
    private let startURL: URL?

    public init(player: MpvPlayer, startURL: URL? = nil) {
        self.player = player
        self.startURL = startURL
    }

    public func makeUIViewController(context: Context) -> SurfaceViewController {
        SurfaceViewController(player: player, startURL: startURL)
    }

    public func updateUIViewController(_ uiViewController: SurfaceViewController, context: Context) {}

    public final class SurfaceViewController: UIViewController {
        private let player: MpvPlayer
        private let startURL: URL?

        init(player: MpvPlayer, startURL: URL?) {
            self.player = player
            self.startURL = startURL
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        public override func viewDidLoad() {
            super.viewDidLoad()
            player.surface.install(in: view)
            if let startURL { player.loadFile(startURL) }
        }

        public override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            player.surface.layoutSurface(in: view.bounds)
        }
    }
}
