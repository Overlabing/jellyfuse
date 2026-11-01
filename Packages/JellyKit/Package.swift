// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JellyKit",
    platforms: [.tvOS(.v17)],
    products: [
        .library(name: "PlayerCore", targets: ["PlayerCore"]),
        .library(name: "LibraryKit", targets: ["LibraryKit"]),
    ],
    dependencies: [
        // Only the LGPL product. Never a "-GPL" product.
        .package(url: "https://github.com/mpvkit/MPVKit", exact: "1.0.0"),
        .package(url: "https://github.com/jellyfin/jellyfin-sdk-swift", from: "3.3.0"),
    ],
    targets: [
        .target(name: "PlayerCore", dependencies: [
            .product(name: "MPVKit", package: "MPVKit"),
        ]),
        .target(name: "LibraryKit", dependencies: [
            .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
        ]),
        .testTarget(name: "PlayerCoreTests", dependencies: ["PlayerCore"]),
        .testTarget(name: "LibraryKitTests", dependencies: ["LibraryKit"]),
    ]
)
