#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path .build/cache Sources/Model.swift Sources/Compatibility.swift Sources/Engine.swift Sources/Documents.swift Sources/DocumentFidelity.swift Sources/RichDocuments.swift Sources/PDFText.swift Sources/NativeOffice.swift Sources/NativeOfficeScript.swift Sources/RARStore.swift Sources/ModuleRendering.swift Sources/ModuleMedia.swift Sources/ModulePixels.swift Sources/ModuleBackgrounds.swift Tests/DocumentEngine/Matrix.swift Tests/DocumentEngine/main.swift -o .build/document-check -framework AppKit -framework AVFoundation -framework PDFKit -framework CoreImage -framework Vision -framework ImageIO -framework CoreText -framework JavaScriptCore
if [[ "${1:-}" == "--build-gui" ]]; then
  app="$PWD/.build/DocumentValidation.app"
  mkdir -p "$app/Contents/MacOS"
  cp .build/document-check "$app/Contents/MacOS/DocumentCheck"
  python3 - "$app" "$PWD" "${2:-}" <<'PYINFO'
import sys,plistlib
from pathlib import Path
app,root,mode=sys.argv[1:]
p=Path(app)/'Contents/Info.plist'
p.write_bytes(plistlib.dumps({'CFBundleIdentifier':'io.joseph.clementine.documentfidelity','DocumentMatrixAffected':mode=='--affected','CFBundleName':'Clémentine Test Documents','CFBundleExecutable':'DocumentCheck','CFBundlePackageType':'APPL','NSAppleEventsUsageDescription':'Vérifie les exports Pages, Numbers et Keynote avec des copies de démonstration.','DocumentTestRoot':root+'/.build/document-fidelity-results','ClementineSourceRoot':root}))
PYINFO
  codesign --force --sign - "$app"
  exit 0
fi
CLEMENTINE_TOOLS="$PWD/Resources/Tools" CLEMENTINE_RESOURCES="$PWD/Resources" CLEMENTINE_OFFICE="${CLEMENTINE_OFFICE:-/Applications/Clémentine.app/Contents/Helpers/LibreOffice.app/Contents/MacOS/soffice}" DOCUMENT_TEST_ROOT="$PWD/.build/document-engine-results" .build/document-check
