#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/cache .build/PreviewLifecycleCheck.app/Contents/MacOS .build/preview-lifecycle-results
sources=(Sources/*.swift)
sources=(${sources:#Sources/Main.swift})
xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path .build/cache \
  "${sources[@]}" Tests/PreviewLifecycle/Main.swift -o .build/PreviewLifecycleCheck.app/Contents/MacOS/PreviewLifecycleCheck \
  -framework AppKit -framework SwiftUI -framework AVKit -framework AVFoundation \
  -framework PDFKit -framework Vision -framework CoreImage -framework ImageIO \
  -framework CoreText -framework ServiceManagement -framework JavaScriptCore \
  -framework QuickLookThumbnailing -framework QuickLookUI -framework CoreServices
python3 - <<'PY'
from pathlib import Path
import plistlib
Path('.build/PreviewLifecycleCheck.app/Contents/Info.plist').write_bytes(plistlib.dumps({
 'CFBundleExecutable':'PreviewLifecycleCheck','CFBundleIdentifier':'io.joseph.clementine.previewlifecyclecheck',
 'CFBundleName':'PreviewLifecycleCheck','CFBundlePackageType':'APPL',
 'PreviewTestRoot':str(Path('.build/preview-lifecycle-results').resolve())}))
PY
codesign --force --sign - .build/PreviewLifecycleCheck.app
ffmpeg='.build/Clémentine.app/Contents/Resources/Tools/ffmpeg'
"$ffmpeg" -hide_banner -loglevel error -y -f lavfi -i color=c=orange:s=320x240:r=10 -t 0.5 -c:v libx264 -pix_fmt yuv420p .build/preview-lifecycle-results/Video.mp4
"$ffmpeg" -hide_banner -loglevel error -y -f lavfi -i sine=frequency=440:sample_rate=44100 -t 0.5 .build/preview-lifecycle-results/Audio.wav
.build/PreviewLifecycleCheck.app/Contents/MacOS/PreviewLifecycleCheck
