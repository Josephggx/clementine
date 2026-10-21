#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path
import subprocess,plistlib,os
root=Path.cwd(); app=root/'.build'/os.environ.get('CLEMENTINE_TEST_APP','OnboardingCheck.app')
executable=app.stem
(app/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
sources=[str(p) for p in (root/'Sources').glob('*.swift') if p.name!='Main.swift']
tests=[str(p) for p in (root/'Tests/Onboarding').glob('*.swift')]
cmd=['xcrun','swiftc','-swift-version','5','-target','arm64-apple-macosx14.0','-module-cache-path',str(root/'.build/cache'),*sources,*tests,'-o',str(app/'Contents/MacOS'/executable)]
for f in ['AppKit','SwiftUI','AVKit','AVFoundation','PDFKit','Vision','CoreImage','ImageIO','CoreText','ServiceManagement','JavaScriptCore','CoreServices']:cmd+=['-framework',f]
subprocess.run(cmd,check=True)
resources=app/'Contents/Resources';resources.mkdir(exist_ok=True)
link=resources/'Demo'
if not link.exists():link.symlink_to(root/'Resources/Demo')
localization=resources/'Localization'
if not localization.exists():localization.symlink_to(root/'Resources/Localization')
identity=os.environ.get('CLEMENTINE_TEST_BUNDLE_ID','io.joseph.clementine.onboardingcheck')
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':executable,'CFBundleIdentifier':identity,'CFBundleName':executable,'CFBundlePackageType':'APPL','NSAppleEventsUsageDescription':'Essais isolés des autorisations pour les conversions natives Clémentine.','TestMode':os.environ.get('CLEMENTINE_TEST_MODE',''),'TestRoot':str(root/'.build/onboarding-results')}))
subprocess.run(['codesign','--force','--sign','-','--identifier',identity,'--requirements','=designated => identifier "'+identity+'"',str(app)],check=True)
print(app)
PY
