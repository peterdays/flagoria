#!/usr/bin/env bash
# Drive: open Map Settings under xvfb and save a PNG under artifacts/.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"
ART=".cursor/skills/verify-flagoria/artifacts"
RUN=".cursor/skills/verify-flagoria/.run"
mkdir -p "$ART" "$RUN"

if [[ -z "${GODOT:-}" ]]; then
  echo "drive-map-settings: set GODOT" >&2
  exit 1
fi
if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "drive-map-settings: xvfb-run not available; skip visual proof" >&2
  exit 2
fi

SCRIPT_RES="res://.cursor/skills/verify-flagoria/bin/capture_map_settings.gd"
out_png="${ART}/map_settings.png"

set +e
xvfb-run -a -s "-screen 0 1280x720x24" \
  "$GODOT" --path "$ROOT" --rendering-driver opengl3 \
  --script "${SCRIPT_RES}" >"${ART}/map_settings.log" 2>&1
status=$?
set -e
cat "${ART}/map_settings.log"
if [[ "${status}" -ne 0 ]]; then
  echo "drive-map-settings: capture failed (exit ${status})" >&2
  exit "${status}"
fi
# Script writes via user:// or res path — prefer copying from artifacts target the gd script uses
if [[ ! -f "${out_png}" ]]; then
  # Fallback: look for capture next to project user dir is unreliable; require script to write ART path via OS
  echo "drive-map-settings: missing ${out_png}" >&2
  exit 1
fi
echo "drive-map-settings: wrote ${out_png}"
