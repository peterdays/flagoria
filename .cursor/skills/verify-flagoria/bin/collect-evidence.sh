#!/usr/bin/env bash
# Collect evidence: copy a run's game.log and scratch user:// (saves/, *.cfg)
# into artifacts/out/runs/<run-id>/ and write summary.txt there. Reads .run/
# only; bin/cleanup.sh calls it for every run before it removes .run/.
#
# Usage: bin/collect-evidence.sh <run-id>
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"
source "${ROOT}/.cursor/skills/verify-flagoria/bin/run_lib.sh"

id="${1:-}"
if [[ -z "${id}" || $# -ne 1 || "${id}" == */* || ! -d "${RUN_ROOT}/${id}" ]]; then
  echo "usage: bin/collect-evidence.sh <run-id>   (a dir under .run/)" >&2
  exit 2
fi
run="${RUN_ROOT}/${id}"
out="${EVIDENCE_ROOT}/${id}"
mkdir -p "${out}"
log="${run}/game.log"
[[ -f "${log}" ]] && cp "${log}" "${out}/game.log"

user="${run}/xdg/data/godot/app_userdata/Flagoria"
if [[ -d "${user}" ]]; then
  mkdir -p "${out}/user"
  [[ -d "${user}/saves" ]] && cp -R "${user}/saves" "${out}/user/"
  find "${user}" -maxdepth 1 -name '*.cfg' -exec cp {} "${out}/user/" \;
fi

# The result: the drive's done line; else idle; else how the game ended.
result="unknown"
if grep -q '^VERIFY_DONE ok$' "${log}" 2>/dev/null; then
  result="ok"
elif grep -q '^VERIFY_DONE fail$' "${log}" 2>/dev/null; then
  result="fail"
elif grep -q '^VERIFY_IDLE' "${log}" 2>/dev/null; then
  result="idle (then stopped by cleanup or killed)"
elif [[ -f "${run}/exit" ]]; then
  code="$(cat "${run}/exit")"
  if ((code > 128)); then
    result="killed (signal $((code - 128)), no VERIFY_DONE)"
  else
    result="exited ${code} without VERIFY_DONE"
  fi
else
  # launch.sh returned before the exit (a timeout): stopped by cleanup or killed.
  result="killed (no VERIFY_DONE)"
fi

version="unknown"
if found="$(command -v "${GODOT:-godot}" 2>/dev/null)"; then
  version="$("${found}" --version 2>/dev/null | head -n 1)" || version="unknown"
fi
commit="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
[[ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]] && commit="${commit} (uncommitted changes)"
steps="$(sed -n 's/^VERIFY_STEP //p' "${log}" 2>/dev/null | paste -sd ' ' -)"

{
  echo "run: ${id}"
  echo "drive: $(cat "${run}/drive" 2>/dev/null || echo unknown)"
  echo "commit: ${commit}"
  echo "godot: ${version}"
  echo "steps: ${steps:-none}"
  echo "result: ${result}"
  echo "snapshots: $(cd "${out}" && ls -1 [0-9][0-9]-*.json 2>/dev/null | paste -sd ' ' - || true)"
} >"${out}/summary.txt"
echo "collect-evidence: ${out#"${ROOT}"/} (result: ${result})"
