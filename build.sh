#!/bin/zsh
set -eu
cd "$(dirname "$0")"
app="${CLEMENTINE_APP_PATH:-/Applications/Clémentine.app}"
mkdir -p .build/cache
sparkle_root=$(zsh Scripts/prepare-sparkle.sh)
test_sources=()
test_flags=()
if [[ "${CLEMENTINE_INTERNAL_TESTS:-0}" == "1" ]]; then
  test_sources=(Tests/SelfTests.swift Tests/ConversionParityTests.swift)
  test_flags=(-D CLEMENTINE_INTERNAL_TESTS)
fi
compiled_binary=$(mktemp "$PWD/.build/Clementine.XXXXXX")
trap 'rm -f "$compiled_binary"' EXIT
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path .build/cache Sources/*.swift "${test_sources[@]}" "${test_flags[@]}" -o "$compiled_binary" -framework AppKit -framework SwiftUI -framework AVKit -framework AVFoundation -framework PDFKit -framework Vision -framework CoreImage -framework ImageIO -framework CoreText -framework ServiceManagement -framework JavaScriptCore -framework QuickLookThumbnailing -framework CoreServices -F "$sparkle_root" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if [[ ! -x "$app/Contents/Helpers/LibreOffice.app/Contents/MacOS/soffice" ]]; then
  ./prepare-runtime.sh
fi
cp -R Resources/. "$app/Contents/Resources/"
cp THIRDPARTY.txt "$app/Contents/Resources/THIRDPARTY.txt"
mkdir -p "$app/Contents/Frameworks"
ditto "$sparkle_root/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp "$sparkle_root/LICENSE" "$app/Contents/Resources/Sparkle-LICENSE.txt"
# The editable icon bitmap is generated in a temporary folder; only the icns ships.
rm -f "$app/Contents/Resources/Icon.png" "$app/Contents/Resources/AppIconLight.png"
cp "$compiled_binary" "$app/Contents/MacOS/Clementine"
cp Info.plist "$app/Contents/Info.plist"
# Keep the bundled office runtime's signature stable across app updates.
for tool_binary in "$app/Contents/Resources/Tools/ffmpeg" "$app/Contents/Resources/Tools/ffprobe"; do
  codesign --force --sign - "$tool_binary"
done
# Keep a stable designated requirement across local prerelease builds. TCC uses
# this identity for Accessibility; a plain ad-hoc signature changes its CDHash
# at every update and can leave a stale, apparently enabled row in Settings.
codesign --force --sign - --identifier "io.joseph.clementine.desktop" \
  --requirements '=designated => identifier "io.joseph.clementine.desktop"' \
  --entitlements Entitlements.plist "$app"
codesign --verify --deep --strict "$app"
test -x "$app/Contents/Resources/Tools/ffprobe"
echo "Application construite : $app"
