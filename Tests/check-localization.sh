#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/cache .build/LanguageCheck.app/Contents/MacOS .build/LanguageCheck.app/Contents/Resources
sources=(Sources/*.swift)
sources=(${sources:#Sources/Main.swift})
xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path .build/cache \
  "${sources[@]}" Tests/Localization/Main.swift -o .build/LanguageCheck.app/Contents/MacOS/LanguageCheck \
  -framework AppKit -framework SwiftUI -framework AVKit -framework AVFoundation \
  -framework PDFKit -framework Vision -framework CoreImage -framework ImageIO \
  -framework CoreText -framework ServiceManagement -framework JavaScriptCore \
  -framework QuickLookThumbnailing -framework CoreServices
cp -R Resources/Localization Resources/Demo .build/LanguageCheck.app/Contents/Resources/
python3 - <<'PY'
import plistlib
from pathlib import Path
Path('.build/LanguageCheck.app/Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleExecutable':'LanguageCheck','CFBundleIdentifier':'io.joseph.clementine.languagecheck',
    'CFBundleName':'LanguageCheck','CFBundlePackageType':'APPL',
    'CFBundleDevelopmentRegion':'fr','CFBundleLocalizations':['fr','en']}))
PY
codesign --force --sign - .build/LanguageCheck.app
.build/LanguageCheck.app/Contents/MacOS/LanguageCheck
