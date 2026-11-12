#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/clementine-news.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -swift-version 5 -module-cache-path .build/cache Sources/WhatsNew.swift Tests/News/main.swift -o "$check_dir/check"
"$check_dir/check"
