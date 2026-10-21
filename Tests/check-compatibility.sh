#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/clementine-parity.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -swift-version 5 -module-cache-path .build/cache Sources/Localization.swift Sources/Compatibility.swift Sources/Model.swift Sources/WheelGeometry.swift Tests/Compatibility/main.swift -o "$check_dir/check" -framework AppKit -framework SwiftUI
"$check_dir/check" Tests/Compatibility/reference.json
