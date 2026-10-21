#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/cache .build/WorkspaceFilesCheck.app/Contents/MacOS .build/WorkspaceFilesCheck.app/Contents/Resources
sources=(Sources/*.swift)
sources=(${sources:#Sources/Main.swift})
xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path .build/cache \
  "${sources[@]}" Tests/WorkspaceFiles/Main.swift -o .build/WorkspaceFilesCheck.app/Contents/MacOS/WorkspaceFilesCheck \
  -framework AppKit -framework SwiftUI -framework AVKit -framework AVFoundation \
  -framework PDFKit -framework Vision -framework CoreImage -framework ImageIO \
  -framework CoreText -framework ServiceManagement -framework JavaScriptCore \
  -framework QuickLookThumbnailing -framework CoreServices
cp -R Resources/Localization Resources/Demo .build/WorkspaceFilesCheck.app/Contents/Resources/
python3 - <<'PY'
import plistlib
from pathlib import Path
Path('.build/WorkspaceFilesCheck.app/Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleExecutable':'WorkspaceFilesCheck','CFBundleIdentifier':'io.joseph.clementine.workspacefilescheck',
    'CFBundleName':'WorkspaceFilesCheck','CFBundlePackageType':'APPL'}))
PY
codesign --force --sign - .build/WorkspaceFilesCheck.app
.build/WorkspaceFilesCheck.app/Contents/MacOS/WorkspaceFilesCheck
