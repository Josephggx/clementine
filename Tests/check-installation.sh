#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/cache
xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 \
  -module-cache-path .build/cache Sources/Localization.swift Sources/ApplicationInstallation.swift \
  Tests/Installation/main.swift -framework AppKit -o .build/installation-check
.build/installation-check
