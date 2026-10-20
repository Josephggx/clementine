#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

version="${CLEMENTINE_VERSION:-0.2.4}"
build_number="${CLEMENTINE_BUILD:-7}"
bundle_id="${CLEMENTINE_BUNDLE_ID:-io.joseph.clementine.beta20261020r2}"
name="Clémentine Beta"
output_root="${CLEMENTINE_OUTPUT_ROOT:-$(dirname "$PWD")}" 
work="$PWD/.build/distribution"
app="$work/$name.app"
volume="$work/volume"
dmg="$output_root/Clementine-Beta-${version}-arm64.dmg"

rm -rf "$work"
mkdir -p "$work" "$volume" "$output_root"

# Copy the already validated standalone build without changing the development app.
ditto "$PWD/.build/Clémentine.app" "$app"
cp THIRDPARTY.txt "$app/Contents/Resources/THIRDPARTY.txt"

plist="$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $name" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $name" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$plist"
/usr/libexec/PlistBuddy -c "Add :ClementineDistributionChannel string beta" "$plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Set :ClementineDistributionChannel beta" "$plist"

strings="$app/Contents/Resources/fr.lproj/InfoPlist.strings"
sed -i '' 's/Clémentine/Clémentine Beta/g' "$strings"

for tool_binary in "$app/Contents/Resources/Tools/ffmpeg" "$app/Contents/Resources/Tools/ffprobe"; do
  codesign --force --sign - "$tool_binary"
done
codesign --force --sign - --identifier "$bundle_id" \
  --requirements "=designated => identifier \"$bundle_id\"" \
  --entitlements Entitlements.plist "$app"
codesign --verify --deep --strict "$app"

ditto "$app" "$volume/$name.app"
ln -s /Applications "$volume/Applications"
cat > "$volume/À lire avant installation.txt" <<'EOF'
CLÉMENTINE BETA — INSTALLATION

Configuration requise : Mac Apple Silicon, macOS 14 ou plus récent.

1. Glissez « Clémentine Beta » dans le dossier Applications.
2. Ouvrez « Clémentine Beta ». Cette version de test n’est pas notariée par Apple.
   Si macOS bloque son ouverture, autorisez-la depuis Réglages Système →
   Confidentialité et sécurité, puis réessayez.
3. Suivez les cinq étapes de bienvenue. Les autorisations macOS sont demandées
   à la dernière étape, uniquement lorsque vous choisissez de les accorder.

Cette bêta utilise une identité macOS, des préférences et des autorisations distinctes
de l’app « Clémentine ». Les deux peuvent être installées en parallèle.
Quittez l’app Clémentine habituelle avant de tester les raccourcis de la bêta,
pour éviter que les deux roues réagissent au même glisser-déposer.

Les licences et informations sur les composants embarqués sont disponibles dans
Clémentine Beta.app/Contents/Resources/THIRDPARTY.txt.
EOF

rm -f "$dmg" "$dmg.sha256"
hdiutil create -quiet -volname "$name" -srcfolder "$volume" -ov -format UDZO "$dmg"
(cd "$output_root" && shasum -a 256 "${dmg:t}") > "$dmg.sha256"

echo "$dmg"
