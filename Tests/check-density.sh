#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path .build/cache Sources/Model.swift Sources/Compatibility.swift Sources/Engine.swift Sources/Documents.swift Sources/DocumentFidelity.swift Sources/RichDocuments.swift Sources/PDFText.swift Sources/NativeOffice.swift Sources/NativeOfficeScript.swift Sources/RARStore.swift Sources/ModuleRendering.swift Sources/ModuleMedia.swift Sources/ModulePixels.swift Sources/ModuleBackgrounds.swift Tests/Density/main.swift -o .build/density-check -framework AppKit -framework AVFoundation -framework PDFKit -framework CoreImage -framework Vision -framework ImageIO -framework CoreText -framework JavaScriptCore
CLEMENTINE_TOOLS="$PWD/Resources/Tools" DENSITY_TEST_ROOT="$PWD/.build/density-results" .build/density-check
