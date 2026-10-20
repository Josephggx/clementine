#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/cache
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path .build/cache Sources/Model.swift Sources/Compatibility.swift Sources/Engine.swift Sources/Documents.swift Sources/DocumentFidelity.swift Sources/RichDocuments.swift Sources/PDFText.swift Sources/NativeOffice.swift Sources/NativeOfficeScript.swift Sources/RARStore.swift Sources/ModuleRendering.swift Sources/ModuleMedia.swift Sources/ModulePixels.swift Sources/ModuleBackgrounds.swift Tests/PDFOffice/main.swift -o .build/pdf-office-check -framework AppKit -framework AVFoundation -framework PDFKit -framework CoreImage -framework Vision -framework ImageIO -framework CoreText -framework JavaScriptCore
if [[ "${1:-}" == "--build-gui" ]]; then
  app="$PWD/.build/PDFOfficeValidation.app"
  mkdir -p "$app/Contents/MacOS"
  cp .build/pdf-office-check "$app/Contents/MacOS/PDFOfficeCheck"
  python3 - "$app" "$PWD" <<'PYINFO'
import sys,plistlib
from pathlib import Path
app,root=sys.argv[1:]
(Path(app)/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'io.joseph.clementine.pdfofficevalidation','CFBundleName':'Clémentine Test PDF éditable','CFBundleExecutable':'PDFOfficeCheck','CFBundlePackageType':'APPL','PDFOfficeTestRoot':root+'/.build/pdf-office-results','ClementineSourceRoot':root}))
PYINFO
  codesign --force --sign - "$app"
  exit 0
fi
CLEMENTINE_TOOLS="$PWD/Resources/Tools" CLEMENTINE_RESOURCES="$PWD/Resources" CLEMENTINE_OFFICE="${CLEMENTINE_OFFICE:-/Applications/Clémentine.app/Contents/Helpers/LibreOffice.app/Contents/MacOS/soffice}" .build/pdf-office-check "$PWD/.build/pdf-office-results"
