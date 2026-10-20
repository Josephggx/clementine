#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
version=2.10.0
expected=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
vendor="$PWD/.build/vendor/Sparkle-$version"
archive="$PWD/.build/vendor/Sparkle-$version.tar.xz"
mkdir -p "${archive:h}"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 2 \
    "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" \
    --output "$archive"
fi
actual=$(shasum -a 256 "$archive")
if [[ "${actual%% *}" != "$expected" ]]; then
  echo 'Archive Sparkle invalide ; compilation arrêtée.' >&2
  exit 1
fi
if [[ ! -f "$vendor/Sparkle.framework/Sparkle" ]]; then
  mkdir -p "$vendor"
  tar -xf "$archive" -C "$vendor"
fi
codesign --verify --deep --strict "$vendor/Sparkle.framework"
echo "$vendor"
