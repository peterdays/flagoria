#!/usr/bin/env bash
# Drive: tools/verify.sh (load, parse, headless tests).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"
source "${ROOT}/.cursor/skills/verify-flagoria/bin/run_lib.sh"
ART=".cursor/skills/verify-flagoria/artifacts"
mkdir -p "$ART"

# Same lookup as tools/verify.sh and doctor.sh: GODOT if set, else `godot` on PATH.
export GODOT="${GODOT:-godot}"
if [[ ! -x "$GODOT" ]] && ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "drive-verify: Godot not found: ${GODOT} (put godot on PATH or set GODOT to the editor binary)" >&2
  exit 127
fi

log="${ART}/verify.log"
# In the background so its PID goes to .run/pids before it runs; cleanup.sh
# stops it, and the Godot processes under it, if it hangs. tools/verify.sh
# makes its own scratch user dirs.
"${ROOT}/tools/verify.sh" </dev/null >"${log}" 2>&1 &
pid=$!
run_record "${pid}" verify "verify-$(date +%Y%m%d-%H%M%S)-$$" "${ROOT}/tools/verify.sh"
set +e
wait "${pid}"
status=$?
set -e
cat "${log}"
if [[ "${status}" -ne 0 ]]; then
  echo "drive-verify: tools/verify.sh failed (exit ${status})" >&2
  exit "${status}"
fi
if ! grep -q 'Verification passed.' "${log}"; then
  echo "drive-verify: missing Verification passed." >&2
  exit 1
fi
if ! grep -q 'All tests passed.' "${log}"; then
  echo "drive-verify: missing All tests passed." >&2
  exit 1
fi
echo "drive-verify: OK"
