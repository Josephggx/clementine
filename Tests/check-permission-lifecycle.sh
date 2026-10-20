#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 \
  -module-cache-path .build/cache Sources/PermissionApplicationLeases.swift \
  Tests/Permissions/main.swift -framework AppKit -o .build/permission-lifecycle-check
.build/permission-lifecycle-check
