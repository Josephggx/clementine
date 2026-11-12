#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/cache
xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 \
  -module-cache-path .build/cache Sources/UpdatePreparation.swift \
  Tests/UpdatePreparation/main.swift -o .build/update-preparation-check
.build/update-preparation-check

sparkle_root="$PWD/.build/vendor/Sparkle-2.10.0"
# Uses the project's existing SDK; never starts Sparkle or installs anything.
if [[ -d "$sparkle_root/Sparkle.framework" ]]; then
  xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 \
    -module-cache-path .build/cache -F "$sparkle_root" -framework Sparkle \
    -Xlinker -rpath -Xlinker "$sparkle_root" \
    Sources/AppUpdates.swift Sources/UpdatePreparation.swift \
    Sources/UpdateInstallationReceipt.swift Sources/UpdateFeed.swift \
    Tests/UpdatePreparation/AdapterMain.swift -o .build/update-adapter-check
  .build/update-adapter-check
fi
