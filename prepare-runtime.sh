#!/bin/zsh
set -eu
cd "$(dirname "$0")"
app="${CLEMENTINE_APP_PATH:-/Applications/Clémentine.app}"
if [[ -x "$app/Contents/Helpers/LibreOffice.app/Contents/MacOS/soffice" ]]; then
  echo "Moteur bureautique déjà présent."
  exit 0
fi
installed="/Applications/Clémentine.app/Contents/Helpers/LibreOffice.app"
if [[ "$app" != "/Applications/Clémentine.app" && -x "$installed/Contents/MacOS/soffice" ]]; then
  mkdir -p "$app/Contents/Helpers"
  ditto "$installed" "$app/Contents/Helpers/LibreOffice.app"
  exit 0
fi
runtime_work=$(mktemp -d "${TMPDIR:-/tmp}/clementine-runtime.XXXXXX")
mounted=0
cleanup() {
  if [[ "$mounted" == 1 ]]; then hdiutil detach "$runtime_work/volume" >/dev/null || true; fi
  rm -rf "$runtime_work"
}
trap cleanup EXIT
curl -L --fail --retry 2 https://download.documentfoundation.org/libreoffice/stable/26.8.1/mac/aarch64/LibreOffice_26.8.1_MacOS_aarch64.dmg -o "$runtime_work/LibreOffice.dmg"
hdiutil attach "$runtime_work/LibreOffice.dmg" -nobrowse -readonly -mountpoint "$runtime_work/volume" >/dev/null
mounted=1
mkdir -p "$app/Contents/Helpers"
ditto "$runtime_work/volume/LibreOffice.app" "$app/Contents/Helpers/LibreOffice.app"
echo "Moteur LibreOffice préparé."
