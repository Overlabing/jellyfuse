// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JellyKit",
    platforms: [.tvOS(.v17), .iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PlayerCore", targets: ["PlayerCore"]),
        .library(name: "LibraryKit", targets: ["LibraryKit"]),
        .library(name: "PlaybackEngine", targets: ["PlaybackEngine"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "HomePresentation", targets: ["HomePresentation"]),
        .library(name: "PlayerPresentation", targets: ["PlayerPresentation"]),
        .library(name: "SettingsKit", targets: ["SettingsKit"]),
    ],
    dependencies: [
        // Only the LGPL product. Never a "-GPL" product.
        // Overlabing fork: libmpv + vo_avsamplebuffer (tvOS only binary).
        .package(url: "https://github.com/Overlabing/MPVKit.git", exact: "0.41.0-avsb.2"),
        .package(url: "https://github.com/jellyfin/jellyfin-sdk-swift", from: "3.3.0"),
    ],
    targets: [
        .target(name: "PlayerCore", dependencies: [
            .product(name: "MPVKit", package: "MPVKit"),
        ]),
        .target(name: "LibraryKit", dependencies: [
            .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
        ]),
        .target(name: "PlaybackEngine", dependencies: [
            "LibraryKit",
            .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
        ]),
        .target(name: "DesignSystem"),
        // LibraryKit entries -> DesignSystem display models (pure mappers, no UI).
        .target(name: "HomePresentation", dependencies: ["LibraryKit", "DesignSystem"]),
        // Playback state (tracks, chapters, item) -> the player's content panel model (pure mapper, no UI).
        .target(name: "PlayerPresentation", dependencies: ["LibraryKit", "PlaybackEngine", "DesignSystem"]),
        // Réglages: license manifest + texts (resources), account / build summaries.
        .target(name: "SettingsKit", dependencies: ["LibraryKit"], resources: [.copy("LicenseData")]),
        .testTarget(name: "PlayerCoreTests", dependencies: ["PlayerCore"]),
        .testTarget(name: "LibraryKitTests", dependencies: ["LibraryKit"]),
        .testTarget(name: "PlaybackEngineTests", dependencies: ["PlaybackEngine"]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
        .testTarget(name: "PlayerPresentationTests", dependencies: ["PlayerPresentation", "PlaybackEngine", "LibraryKit", "DesignSystem"]),
        .testTarget(name: "HomePresentationTests", dependencies: ["HomePresentation", "LibraryKit", "DesignSystem"]),
        .testTarget(name: "SettingsKitTests", dependencies: ["SettingsKit", "LibraryKit"]),
    ]
)
