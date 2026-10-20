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
plist="$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Clémentine" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Clémentine" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$plist"
/usr/libexec/PlistBuddy -c "Delete :ClementineDistributionChannel" "$plist" 2>/dev/null || true
codesign --force --sign - --identifier "$bundle_id" \
  --requirements "=designated => identifier \"$bundle_id\"" \
  --entitlements Entitlements.plist "$app"
codesign --verify --deep --strict "$app"
mkdir -p "$work/guide"
cat > "$work/guide/Installation.txt" <<'EOF'
CLÉMENTINE — INSTALLATION

Mac Apple Silicon (M1, M2, M3 ou ultérieur), macOS 14 ou plus récent.

1. Glissez Clémentine dans le dossier Applications.
2. Ouvrez Clémentine depuis Applications.
3. Suivez le guide de démarrage. Si vous choisissez de configurer les accès,
   activez d’abord Accessibilité, puis autorisez les applications Apple proposées.

Cette version est signée localement, sans certificat Developer ID ni notarisation
Apple. macOS peut bloquer sa première ouverture. Dans ce cas, après la tentative
d’ouverture, rendez-vous dans Réglages Système → Confidentialité et sécurité
pour autoriser Clémentine.

Les outils de conversion sont intégrés. Pages, Numbers et Keynote doivent être
installés pour les opérations nécessitant ces applications.

Licences : Clémentine.app/Contents/Resources/THIRDPARTY.txt.
EOF
# Keep the visible installation window focused on the two drag targets.
cp "$work/guide/Installation.txt" "$app/Contents/Resources/Installation.txt"
codesign --force --sign - --identifier "$bundle_id" \
  --requirements "=designated => identifier \"$bundle_id\"" \
  --entitlements Entitlements.plist "$app"
codesign --verify --deep --strict "$app"

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
(cd "$output_root" && shasum -a 256 "${dmg:t}") > "$dmg.sha256"
echo "$dmg"
