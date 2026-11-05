#!/usr/bin/env bash
# Drive: open the join-address letter keyboard under xvfb → docs/screenshots/letter_keyboard_480x270.png
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"
source "${ROOT}/.cursor/skills/verify-flagoria/bin/run_lib.sh"
ART=".cursor/skills/verify-flagoria/artifacts"
mkdir -p "$ART" docs/screenshots
run_find_godot drive-letter-keyboard
xvfb="$(command -v xvfb-run)" || { echo "drive-letter-keyboard: xvfb-run not available; skip" >&2; exit 2; }
run_new letter-keyboard
out_png="docs/screenshots/letter_keyboard_480x270.png"
SCRIPT_RES="res://.cursor/skills/verify-flagoria/bin/capture_letter_keyboard.gd"
"${xvfb}" -a -s "-screen 0 1280x720x24" \
  "${GODOT_EXE}" --path "$ROOT" --rendering-driver opengl3 \
  --script "${SCRIPT_RES}" </dev/null >"${ART}/letter_keyboard_screenshot.log" 2>&1 &
pid=$!
run_record "${pid}" xvfb-run "${RUN_ID}" "${xvfb}"
run_record_godot_children "${pid}" "${RUN_ID}" || true
set +e
wait "${pid}"
status=$?
set -e
cat "${ART}/letter_keyboard_screenshot.log"
if [[ "${status}" -ne 0 ]]; then
  echo "drive-letter-keyboard: capture failed (exit ${status})" >&2
  exit "${status}"
fi
if [[ ! -f "${out_png}" ]]; then
  echo "drive-letter-keyboard: missing ${out_png}" >&2
  exit 1
fi
echo "drive-letter-keyboard: wrote ${out_png}"
