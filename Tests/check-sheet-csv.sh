#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/cache .build/sheet-csv-results
python3 Tests/SheetCSV/create_fixture.py .build/sheet-csv-results
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path .build/cache Sources/Localization.swift Sources/Model.swift Sources/Compatibility.swift Sources/Engine.swift Sources/PDFSplitEngine.swift Sources/Documents.swift Sources/DocumentFidelity.swift Sources/RichDocuments.swift Sources/PDFText.swift Sources/NativeOffice.swift Sources/NativeOfficeScript.swift Sources/RARStore.swift Sources/ModuleRendering.swift Sources/ModuleMedia.swift Sources/ModulePixels.swift Sources/ModuleBackgrounds.swift Tests/SheetCSV/main.swift -o .build/sheet-csv-check -framework AppKit -framework AVFoundation -framework PDFKit -framework CoreImage -framework Vision -framework ImageIO -framework CoreText -framework JavaScriptCore
if [[ "${1:-}" == "--build-gui" ]]; then
  app="$PWD/.build/SheetCSVValidation.app"
  mkdir -p "$app/Contents/MacOS"
  cp .build/sheet-csv-check "$app/Contents/MacOS/SheetCSVCheck"
  python3 - "$app" "$PWD" <<'PYINFO'
import sys,plistlib
from pathlib import Path
app,root=sys.argv[1:]
(Path(app)/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'io.joseph.clementine.sheetcsvvalidation','CFBundleName':'Clémentine Test Feuilles CSV','CFBundleExecutable':'SheetCSVCheck','CFBundlePackageType':'APPL','SheetCSVRoot':root+'/.build/sheet-csv-results','ClementineSourceRoot':root}))
PYINFO
  codesign --force --sign - "$app"
  exit 0
fi
CLEMENTINE_OFFICE="${CLEMENTINE_OFFICE:-/Applications/Clémentine.app/Contents/Helpers/LibreOffice.app/Contents/MacOS/soffice}" SHEET_CSV_ROOT="$PWD/.build/sheet-csv-results" .build/sheet-csv-check
