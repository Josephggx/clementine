#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."

export CLEMENTINE_OFFICE="${CLEMENTINE_OFFICE:-$PWD/.build/Clémentine.app/Contents/Helpers/LibreOffice.app/Contents/MacOS/soffice}"

checks=(
  check-compatibility.sh
  check-drag.sh
  check-workspace-files.sh
  check-modules.sh
  check-documents.sh
  check-markdown.sh
  check-pdf-office.sh
  check-pdf-layout.sh
  check-sheet-csv.sh
  check-density.sh
)

for check in $checks; do
  echo "== ${check%.sh} =="
  "./Tests/$check"
done

echo "PASS ${#checks[@]} suites Clémentine"
