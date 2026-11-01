#!/usr/bin/env bash
# Launch: start a drive in the background from a scratch user dir, print its
# ready, step and done lines as they come, and exit with the drive's result.
#
# Usage: bin/launch.sh <drive.gd> [--display]
#   <drive.gd> is relative to the skill dir (drives/wait.gd), to the repo, or
#   a res:// path. --display runs under xvfb-run with opengl3 instead of
#   --headless.
#
# Exit: 0 when the drive prints VERIFY_DONE ok and quits 0; 1 on VERIFY_DONE
# fail, or when the game exits without a done line. On VERIFY_IDLE it exits 0
# and leaves the game running for bin/cleanup.sh. VERIFY_READY_TIMEOUT (60 s)
# bounds the wait for the ready line, VERIFY_DRIVE_TIMEOUT (300 s) the wait
# after it; on a timeout the game is left running and launch exits 1.
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

ready_timeout="${VERIFY_READY_TIMEOUT:-60}"
drive_timeout="${VERIFY_DRIVE_TIMEOUT:-300}"
shown=0      # protocol lines already printed
ready=0
deadline=$((SECONDS + ready_timeout))
# Prints the protocol lines added to the log since the last call.
stream() {
  local lines
  lines="$(grep -E '^VERIFY_(READY|STEP|DONE|IDLE)( |$)' "${log}" || true)"
  [[ -z "${lines}" ]] && return 0
  tail -n "+$((shown + 1))" <<<"${lines}"
  shown="$(wc -l <<<"${lines}")"
}
while [[ -d "/proc/${pid}" ]]; do
  stream
  if [[ ${ready} -eq 0 ]] && grep -q '^VERIFY_READY ' "${log}"; then
    ready=1
    deadline=$((SECONDS + drive_timeout))
  fi
  if grep -q '^VERIFY_IDLE' "${log}"; then
    exit 0
  fi
  if ((SECONDS >= deadline)); then
    what="VERIFY_READY within ${ready_timeout} s"
    [[ ${ready} -eq 1 ]] && what="VERIFY_DONE or VERIFY_IDLE within ${drive_timeout} s of the ready line"
    echo "launch: no ${what}; still running, stop it with bin/cleanup.sh. Log tail:" >&2
    tail -n 20 "${log}" >&2
    exit 1
  fi
  sleep 0.1
done
code=0
wait "${pid}" || code=$?
stream
if grep -q '^VERIFY_DONE ok$' "${log}" && [[ ${code} -eq 0 ]]; then
  exit 0
fi
if grep -q '^VERIFY_DONE fail$' "${log}"; then
  echo "launch: the drive failed (exit ${code}). Log tail:" >&2
elif grep -q '^VERIFY_DONE ok$' "${log}"; then
  echo "launch: VERIFY_DONE ok, but the game exited ${code}. Log tail:" >&2
elif [[ ${ready} -eq 1 ]] || grep -q '^VERIFY_READY ' "${log}"; then
  echo "launch: the game exited ${code} without a VERIFY_DONE line. Log tail:" >&2
else
  echo "launch: the game exited ${code} before VERIFY_READY. Log tail:" >&2
fi
tail -n 20 "${log}" >&2
exit 1
