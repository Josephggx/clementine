#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path
import subprocess,plistlib
root=Path.cwd(); app=root/'.build/OnboardingCheck.app'
(app/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
sources=[str(p) for p in (root/'Sources').glob('*.swift') if p.name!='Main.swift']
cmd=['xcrun','swiftc','-swift-version','5','-target','arm64-apple-macosx14.0','-module-cache-path',str(root/'.build/cache'),*sources,str(root/'Tests/Onboarding/Main.swift'),'-o',str(app/'Contents/MacOS/OnboardingCheck')]
for f in ['AppKit','SwiftUI','AVKit','AVFoundation','PDFKit','Vision','CoreImage','ImageIO','CoreText','ServiceManagement','JavaScriptCore','CoreServices']:cmd+=['-framework',f]
subprocess.run(cmd,check=True)
resources=app/'Contents/Resources';resources.mkdir(exist_ok=True)
link=resources/'Demo'
if not link.exists():link.symlink_to(root/'Resources/Demo')
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'OnboardingCheck','CFBundleIdentifier':'io.joseph.clementine.onboardingcheck','CFBundleName':'Vérification onboarding','CFBundlePackageType':'APPL','TestRoot':str(root/'.build/onboarding-results')}))
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
print(app)
PY
