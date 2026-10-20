#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path
import subprocess,plistlib
root=Path.cwd();app=root/'.build/PenValidation.app'
(app/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
sources=[str(p) for p in (root/'Sources').glob('*.swift') if p.name!='Main.swift']
cmd=['xcrun','swiftc','-O','-swift-version','5','-target','arm64-apple-macosx14.0','-module-cache-path',str(root/'.build/cache'),*sources,str(root/'Tests/PenUI/Main.swift'),'-o',str(app/'Contents/MacOS/PenCheck')]
for framework in ['AppKit','SwiftUI','AVKit','AVFoundation','PDFKit','Vision','CoreImage','ImageIO','CoreText','ServiceManagement','JavaScriptCore','QuickLookThumbnailing']:cmd+=['-framework',framework]
subprocess.run(cmd,check=True)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'PenCheck','CFBundleIdentifier':'io.joseph.clementine.penvalidation','CFBundleName':'Clémentine Test Stylo','CFBundlePackageType':'APPL','PenTestRoot':str(root/'.build/pen-test-results')}))
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
print(app)
PY
