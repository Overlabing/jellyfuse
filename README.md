# jellyfuse-tv

Native Jellyfin client for tvOS, in pure Swift (no JavaScript). Playback is libmpv
(LGPL MPVKit, `vo=gpu-next` on MoltenVK, zero-copy VideoToolbox).

## Layout

- `Apps/JellyTV`: the tvOS app (SwiftUI).
- `Packages/JellyKit`: local package. `PlayerCore` (mpv facade + video surface), `LibraryKit` (Jellyfin SDK facade, session, keychain).
- `docs/lessons-learned.md`: hard-won notes from the Phase 0 spike.

## Build

```sh
xcodegen generate
xcodebuild -project JellyTV.xcodeproj -scheme JellyTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build
```

The app plays the stream passed as launch argument `-url <stream url>`.
