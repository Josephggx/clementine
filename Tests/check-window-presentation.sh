#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/cache
sources=(Sources/*.swift)
sources=(${sources:#Sources/Main.swift})
xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path .build/cache \
  "${sources[@]}" Tests/WindowPresentation/Main.swift -o .build/window-presentation-check \
  -framework AppKit -framework SwiftUI -framework AVKit -framework AVFoundation \
  -framework PDFKit -framework Vision -framework CoreImage -framework ImageIO \
  -framework CoreText -framework ServiceManagement -framework JavaScriptCore \
  -framework QuickLookThumbnailing -framework CoreServices
.build/window-presentation-check
