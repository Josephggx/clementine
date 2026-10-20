#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
# Builds the production uploader in isolation. Uploads require an explicit
# click in the test window; --routes never opens Chrome or sends a file.
python3 - <<'PY'
from pathlib import Path
import plistlib, subprocess
root = Path.cwd()
app = root / '.build/FinovoxCheck.app'
binary = app / 'Contents/MacOS/FinovoxCheck'
binary.parent.mkdir(parents=True, exist_ok=True)
test_root = root / '.build/finovox-check'
test_root.mkdir(parents=True, exist_ok=True)
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleExecutable': 'FinovoxCheck',
    'CFBundleIdentifier': 'io.joseph.clementine.desktop',
    'CFBundleName': 'Clémentine Test Finovox',
    'CFBundlePackageType': 'APPL',
    'TestRoot': str(test_root),
}))
subprocess.run(['xcrun', 'swiftc', '-swift-version', '5',
    '-module-cache-path', str(root / '.build/cache'),
    'Sources/Finovox.swift', 'Sources/FinovoxImportPage.swift',
    'Tests/Finovox/main.swift', '-o', str(binary),
    '-framework', 'AppKit', '-framework', 'SwiftUI',
    '-framework', 'ApplicationServices'], check=True)
subprocess.run(['codesign', '--force', '--sign', '-',
    '--identifier', 'io.joseph.clementine.desktop',
    '--requirements', '=designated => identifier "io.joseph.clementine.desktop"',
    str(app)], check=True)
print(binary)
PY
.build/FinovoxCheck.app/Contents/MacOS/FinovoxCheck --routes
