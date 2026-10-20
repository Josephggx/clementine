#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path
import subprocess,plistlib
root=Path.cwd();app=root/'.build/ModuleRegression.app';(app/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
sources=[str(p) for p in (root/'Sources').glob('*.swift') if p.name!='Main.swift']
cmd=['xcrun','swiftc','-O','-swift-version','5','-target','arm64-apple-macosx14.0','-module-cache-path',str(root/'.build/cache'),*sources,str(root/'Tests/Modules/Main.swift'),'-o',str(app/'Contents/MacOS/ModuleRegression')]
for f in ['AppKit','SwiftUI','AVKit','AVFoundation','PDFKit','Vision','CoreImage','ImageIO','CoreText','ServiceManagement','JavaScriptCore']:cmd+=['-framework',f]
subprocess.run(cmd,check=True)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'ModuleRegression','CFBundleIdentifier':'io.joseph.clementine.moduleregression','CFBundleName':'Clémentine Test Modules','CFBundlePackageType':'APPL','ProjectRoot':str(root)}))
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
print(app)
PY
