#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

version="${CLEMENTINE_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)}"
build_number="${CLEMENTINE_BUILD:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)}"
output_root="${CLEMENTINE_OUTPUT_ROOT:-$(dirname "$PWD")}"
work="$PWD/.build/distribution-standard"
volume="$work/volume"
app="$volume/Clémentine.app"
bundle_id="io.joseph.clementine.desktop"
dmg="$output_root/Clementine-${version}-arm64.dmg"

# Package the verified build; never replace the installed app.
codesign --verify --deep --strict "$PWD/.build/Clémentine.app"
rm -rf "$work"
mkdir -p "$volume" "$output_root"
ditto "$PWD/.build/Clémentine.app" "$app"
# The DMG must contain the exact signed bundle used by in-app updates. Rewriting
# Info.plist or inserting a guide here would create two incompatible delta bases
# with the same build number. Installation instructions live in the README.
python3 - "$app" "$version" "$build_number" "$bundle_id" <<'CHECK_BUNDLE'
import plistlib, sys
from pathlib import Path
info = plistlib.loads((Path(sys.argv[1]) / "Contents/Info.plist").read_bytes())
expected = dict(zip(["CFBundleShortVersionString", "CFBundleVersion", "CFBundleIdentifier"], sys.argv[2:]))
if any(info.get(key) != value for key, value in expected.items()):
    raise SystemExit("Rebuild Clémentine with the requested version and identity before packaging.")
CHECK_BUNDLE

packaging_python="$PWD/.build/packaging-python"
if ! PYTHONPATH="$packaging_python" python3 -c 'import dmgbuild, ds_store, mac_alias' 2>/dev/null; then
  python3 -m pip install --disable-pip-version-check --target "$packaging_python" \
    -r Scripts/requirements-packaging.txt
fi
xcrun swiftc -module-cache-path .build/cache Scripts/generate-installer-background.swift \
  -o "$work/generate-background" -framework AppKit -framework ImageIO
"$work/generate-background" "$work/background.tiff" "$version"
PYTHONPATH="$packaging_python" python3 -m dmgbuild -s Scripts/dmg-settings.py \
  -D app="$app" -D background="$work/background.tiff" "Clémentine" "$dmg"
python3 Scripts/prepare-update.py "$dmg" --verify-archive-only
python3 - "$dmg" "$PWD/.build/Clémentine.app" <<'CHECK_CONTENTS'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("updates", "Scripts/prepare-update.py")
updates = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updates)
archive, built = map(Path, sys.argv[1:])
manifest = updates.bundle_manifest(updates.extracted_app(archive))
if manifest != updates.bundle_manifest(built):
    raise SystemExit("Installer application differs from the verified build.")
zip_archive = archive.with_suffix(".zip")
if zip_archive.exists() and manifest != updates.bundle_manifest(updates.extracted_app(zip_archive)):
    raise SystemExit("Installer application differs from the published ZIP update.")
print("Verified identical signed application in installer and update archive")
CHECK_CONTENTS
(cd "$output_root" && shasum -a 256 "${dmg:t}") > "$dmg.sha256"
echo "$dmg"
