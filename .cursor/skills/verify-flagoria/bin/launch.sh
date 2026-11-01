#!/usr/bin/env bash
# Launch: start a drive in the background from a scratch user dir and wait
# until it prints the ready line.
#
# Usage: bin/launch.sh <drive.gd> [--display]
#   <drive.gd> is relative to the skill dir (drives/wait.gd), to the repo, or
#   a res:// path. --display runs under xvfb-run with opengl3 instead of
#   --headless. VERIFY_READY_TIMEOUT overrides the 60 s wait.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"
source "${ROOT}/.cursor/skills/verify-flagoria/bin/run_lib.sh"

drive="${1:-}"
display=0
[[ "${2:-}" == "--display" ]] && display=1
if [[ -z "${drive}" || $# -gt 2 || ($# -eq 2 && ${display} -eq 0) ]]; then
  echo "usage: bin/launch.sh <drive.gd> [--display]" >&2
  exit 2
fi
if [[ "${drive}" != res://* ]]; then
  if [[ -f "${SKILL}/${drive}" ]]; then
    drive="res://.cursor/skills/verify-flagoria/${drive}"
  elif [[ -f "${ROOT}/${drive}" ]]; then
    drive="res://${drive}"
  else
    echo "launch: no drive at ${drive}" >&2
    exit 2
  fi
fi

run_find_godot launch
run_new "$(basename "${drive}" .gd)"
log="${RUN_DIR}/game.log"

if [[ ${display} -eq 1 ]]; then
  xvfb="$(command -v xvfb-run)" || { echo "launch: xvfb-run not available" >&2; exit 2; }
  xvfb="$(readlink -f "${xvfb}")"
  "${xvfb}" -a -s "-screen 0 1280x720x24" \
    "${GODOT_EXE}" --path "${ROOT}" --rendering-driver opengl3 --script "${drive}" \
    </dev/null >"${log}" 2>&1 &
  pid=$!
  run_record "${pid}" xvfb-run "${RUN_ID}" "${xvfb}"
  run_record_godot_children "${pid}" "${RUN_ID}" || true
else
  "${GODOT_EXE}" --headless --path "${ROOT}" --script "${drive}" </dev/null >"${log}" 2>&1 &
  pid=$!
  run_record "${pid}" godot "${RUN_ID}" "${GODOT_EXE}"
fi
echo "launch: run=${RUN_ID} pid=${pid} log=${log#"${ROOT}"/}"

timeout="${VERIFY_READY_TIMEOUT:-60}"
for ((i = 0; i < timeout * 10; i++)); do
  if ready="$(grep -m 1 '^VERIFY_READY ' "${log}")"; then
    echo "${ready}"
    exit 0
  fi
  if [[ ! -d "/proc/${pid}" ]]; then
    break
  fi
  sleep 0.1
done
if [[ -d "/proc/${pid}" ]]; then
  echo "launch: no VERIFY_READY within ${timeout} s; still running, stop it with bin/cleanup.sh. Log tail:" >&2
else
  echo "launch: the game exited before VERIFY_READY. Log tail:" >&2
fi
tail -n 20 "${log}" >&2
exit 1
