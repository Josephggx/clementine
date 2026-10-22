#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/clementine-actions.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
sources=(Sources/*.swift)
sources=(${sources:#Sources/Main.swift})
xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path .build/cache "${sources[@]}" Tests/FileActions/main.swift -o "$check_dir/check" -framework AppKit -framework SwiftUI -framework AVKit -framework AVFoundation -framework PDFKit -framework Vision -framework CoreImage -framework ImageIO -framework CoreText -framework ServiceManagement -framework JavaScriptCore -framework QuickLookThumbnailing -framework QuickLookUI -framework CoreServices
CLEMENTINE_OFFICE="$PWD/.build/Clémentine.app/Contents/Helpers/LibreOffice.app/Contents/MacOS/soffice" "$check_dir/check"
