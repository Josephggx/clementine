#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path
import subprocess,plistlib,shutil
root=Path.cwd()
app=root/'.build/WheelRegression.app'
(app/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
sources=[str(p) for p in (root/'Sources').glob('*.swift') if p.name!='Main.swift']
cmd=['xcrun','swiftc','-O','-swift-version','5','-target','arm64-apple-macosx14.0','-module-cache-path',str(root/'.build/cache'),*sources,str(root/'Tests/WheelUI/Main.swift'),'-o',str(app/'Contents/MacOS/WheelRegression')]
for f in ['AppKit','SwiftUI','AVKit','AVFoundation','PDFKit','Vision','CoreImage','ImageIO','CoreText','ServiceManagement','JavaScriptCore']:cmd+=['-framework',f]
subprocess.run(cmd,check=True)
resources=app/'Contents/Resources'
resources.mkdir(exist_ok=True)
shutil.copy2(root/'Resources/WheelHover.wav',resources)
info={'CFBundleExecutable':'WheelRegression','CFBundleIdentifier':'io.joseph.clementine.wheelregression','CFBundleName':'Clémentine Test Drag','CFBundlePackageType':'APPL','TestRoot':str(root/'.build/wheel-test-results')}
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
print(app)
PY
