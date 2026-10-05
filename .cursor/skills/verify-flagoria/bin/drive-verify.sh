#!/usr/bin/env bash
# Drive: tools/verify.sh (load, parse, headless tests).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"
ART=".cursor/skills/verify-flagoria/artifacts"
RUN=".cursor/skills/verify-flagoria/.run"
mkdir -p "$ART" "$RUN"

if [[ -z "${GODOT:-}" ]]; then
  echo "drive-verify: set GODOT to the Godot 4.1 editor binary" >&2
  exit 1
fi

log="${ART}/verify.log"
set +e
./tools/verify.sh >"${log}" 2>&1
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
