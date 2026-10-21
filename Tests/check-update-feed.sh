#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/cache
xcrun swiftc -swift-version 5 -module-cache-path .build/cache Sources/UpdateFeed.swift Tests/UpdateFeed/main.swift -o .build/update-feed-check
.build/update-feed-check
