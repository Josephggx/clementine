#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 \
  -module-cache-path .build/cache Sources/UpdateInstallationReceipt.swift \
  Tests/Updates/ReceiptMain.swift -o .build/update-receipts-check
.build/update-receipts-check
