#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
version="${CLEMENTINE_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)}"
build_number="${CLEMENTINE_BUILD:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)}"
bundle_id="${CLEMENTINE_BUNDLE_ID:-io.joseph.clementine.beta}"
output_root="${CLEMENTINE_OUTPUT_ROOT:-$(dirname "$PWD")/Beta}"
work="$PWD/.build/beta"
app="$work/Clémentine Beta.app"
plist="$work/Info.plist"
mkdir -p "$work" "$output_root"
# Reuse only the standalone runtime; build current sources into a separate app.
# Never overwrite the signed release build that future differential updates use.
if [[ ! -d "$app" ]]; then
  ditto "$PWD/.build/Clémentine.app" "$app"
fi
python3 - "$plist" "$version" "$build_number" "$bundle_id" <<'PY'
from pathlib import Path
import plistlib,sys,os
info=plistlib.loads(Path('Info.plist').read_bytes())
info.update(CFBundleIdentifier=sys.argv[4],CFBundleDisplayName='Clémentine Beta',
    CFBundleName='Clémentine Beta',CFBundleShortVersionString=sys.argv[2],
    CFBundleVersion=sys.argv[3],ClementineDistributionChannel='beta',
    SUEnableAutomaticChecks=False,SUAutomaticallyUpdate=False)
info.pop('SUFeedURL',None)
info['ClementineWheelDiagnostics']=os.environ.get('CLEMENTINE_DIAGNOSTICS') == '1'
Path(sys.argv[1]).write_bytes(plistlib.dumps(info))
PY
CLEMENTINE_APP_PATH="$app" CLEMENTINE_INFO_PLIST="$plist" zsh build.sh
python3 - "$app" <<'PY'
from pathlib import Path
import sys
for p in (Path(sys.argv[1])/'Contents/Resources').glob('*.lproj/InfoPlist.strings'):
    p.write_text(p.read_text().replace('Clémentine','Clémentine Beta'))
PY
codesign --force --sign - --identifier "$bundle_id" \
  --requirements "=designated => identifier \"$bundle_id\"" \
  --entitlements Entitlements.plist "$app"
codesign --verify --deep --strict "$app"
# Portable local test copy; no installation, launch or publication is performed.
ditto "$app" "$output_root/Clémentine Beta.app"
codesign --verify --deep --strict "$output_root/Clémentine Beta.app"
echo "$output_root/Clémentine Beta.app"
