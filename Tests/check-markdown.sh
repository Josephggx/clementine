#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path .build/cache Sources/Model.swift Sources/Compatibility.swift Sources/Engine.swift Sources/Documents.swift Sources/DocumentFidelity.swift Sources/RichDocuments.swift Sources/PDFText.swift Sources/NativeOffice.swift Sources/NativeOfficeScript.swift Sources/RARStore.swift Sources/ModuleRendering.swift Sources/ModuleMedia.swift Sources/ModulePixels.swift Sources/ModuleBackgrounds.swift Tests/Markdown/main.swift -o .build/markdown-check -framework AppKit -framework AVFoundation -framework PDFKit -framework CoreImage -framework Vision -framework ImageIO -framework CoreText -framework JavaScriptCore
if [[ "${1:-}" == "--build-gui" ]]; then
  python3 - <<'PYINFO'
from pathlib import Path
import plistlib,shutil,subprocess
root=Path.cwd();app=root/'.build/MarkdownValidation.app'
(app/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
shutil.copy2(root/'.build/markdown-check',app/'Contents/MacOS/MarkdownCheck')
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'io.joseph.clementine.markdownvalidation','CFBundleExecutable':'MarkdownCheck','CFBundleName':'Clémentine Test Markdown','CFBundlePackageType':'APPL','MarkdownTestRoot':str(root/'.build/markdown-gui-results'),'ClementineSourceRoot':str(root)}))
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
PYINFO
  exit 0
fi
CLEMENTINE_TOOLS="$PWD/Resources/Tools" CLEMENTINE_RESOURCES="$PWD/Resources" MARKDOWN_TEST_ROOT="$PWD/.build/markdown-test-results" .build/markdown-check
