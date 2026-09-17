#!/bin/bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd -P)"
cd "$ROOT" || exit 1
if [[ "$(uname -s)" != Darwin ]]; then echo "Swift testleri macOS gerektirir."; exit 1; fi
swift test
RESULT=$?
echo
read -r -p "Pencereyi kapatmak için Enter..." _
exit "$RESULT"
