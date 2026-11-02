#!/bin/sh
# Copies the license texts of the SwiftPM checkouts into SettingsKit resources, verbatim.
# Usage: Scripts/sync-license-texts.sh <SourcePackages/checkouts dir>
# The upstream texts of the binary mpv stack are committed as fetched; their source URL is `textSource` in licenses.json.
set -eu
checkouts="${1:?usage: sync-license-texts.sh <checkouts dir>}"
out="$(dirname "$0")/../Sources/SettingsKit/LicenseData/texts"
mkdir -p "$out"
cp "$checkouts/MPVKit/LICENSE" "$out/mpvkit.txt"
cp "$checkouts/jellyfin-sdk-swift/LICENSE.md" "$out/jellyfin-sdk-swift.txt"
cp "$checkouts/Get/LICENSE" "$out/get.txt"
cp "$checkouts/swift-atomics/LICENSE.txt" "$out/swift-atomics.txt"
cp "$checkouts/swift-collections/LICENSE.txt" "$out/swift-collections.txt"
cp "$checkouts/swift-system/LICENSE.txt" "$out/swift-system.txt"
cp "$checkouts/swift-nio-transport-services/LICENSE.txt" "$out/swift-nio-transport-services.txt"
{ cat "$checkouts/swift-nio/LICENSE.txt"; printf '\n\n----- NOTICE.txt -----\n\n'; cat "$checkouts/swift-nio/NOTICE.txt"; } > "$out/swift-nio.txt"
cp "$(dirname "$0")/../../../LICENSE" "$out/jellyfuse.txt"
echo "OK: license texts synced"
