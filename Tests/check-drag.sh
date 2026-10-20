#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/clementine-drag.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -O -swift-version 5 -module-cache-path .build/cache Sources/WheelGeometry.swift Sources/WheelDragSession.swift Tests/Drag/main.swift -o "$check_dir/check" -framework AppKit -framework SwiftUI
"$check_dir/check"
