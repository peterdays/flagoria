#!/usr/bin/env bash
# Headless Godot warmup and Android debug export. Single CI export path for APK workflows.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: ci_export_android_apk.sh <apk-output-path>" >&2
  exit 2
fi

apk="$1"
mkdir -p "$(dirname "$apk")"
godot --headless --editor --quit-after 200 --path . || true
godot --headless --path . --export-debug "Android" "$apk"
test -s "$apk"
ls -l "$apk"
