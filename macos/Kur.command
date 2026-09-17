#!/bin/bash
ROOT="$(cd "$(dirname "$0")" && pwd -P)"
bash "$ROOT/scripts/kurulum.sh" install
RESULT=$?
echo
read -r -p "Pencereyi kapatmak için Enter..." _
exit "$RESULT"
