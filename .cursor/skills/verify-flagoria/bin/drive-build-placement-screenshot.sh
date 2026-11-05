#!/usr/bin/env bash
# Drive: interact-mode plank preview under xvfb → docs/screenshots/build_placement_preview.png
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"
source "${ROOT}/.cursor/skills/verify-flagoria/bin/run_lib.sh"
ART=".cursor/skills/verify-flagoria/artifacts"
mkdir -p "$ART" docs/screenshots

run_find_godot drive-build-placement
xvfb="$(command -v xvfb-run)" || {
  echo "drive-build-placement: xvfb-run not available; skip visual proof" >&2
  exit 2
}
xvfb="$(readlink -f "${xvfb}")"
run_new build-placement

SCRIPT_RES="res://.cursor/skills/verify-flagoria/bin/capture_build_placement.gd"
out_png="docs/screenshots/build_placement_preview.png"

"${xvfb}" -a -s "-screen 0 1280x720x24" \
  "${GODOT_EXE}" --path "$ROOT" --rendering-driver opengl3 \
  --script "${SCRIPT_RES}" </dev/null >"${ART}/build_placement_screenshot.log" 2>&1 &
pid=$!
run_record "${pid}" xvfb-run "${RUN_ID}" "${xvfb}"
run_record_godot_children "${pid}" "${RUN_ID}" || true
set +e
wait "${pid}"
status=$?
set -e
cat "${ART}/build_placement_screenshot.log"
if [[ "${status}" -ne 0 ]]; then
  echo "drive-build-placement: capture failed (exit ${status})" >&2
  exit "${status}"
fi
if [[ ! -f "${out_png}" ]]; then
  echo "drive-build-placement: missing ${out_png}" >&2
  exit 1
fi
echo "drive-build-placement: wrote ${out_png}"
