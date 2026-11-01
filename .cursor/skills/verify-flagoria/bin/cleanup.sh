#!/usr/bin/env bash
# Cleanup: stop the processes recorded in .run/pids, by exact PID, then remove
# .run/. A PID is stopped only while it is still the process that was launched
# (see bin/run_lib.sh), so a reused PID or a Godot started by hand is left
# alone. Never kills by name. artifacts/ is never touched.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"
source "${ROOT}/.cursor/skills/verify-flagoria/bin/run_lib.sh"

running() {
  [[ -d "/proc/$1" ]] && [[ "$(awk '{print $3}' "/proc/$1/stat" 2>/dev/null)" != Z ]]
}

is_launched() {
  local pid="$1" kind="$2" id="$3" path="$4"
  running "${pid}" || return 1
  if [[ "${kind}" == godot ]]; then
    # The launched binary, started with this run's scratch user dir.
    [[ "$(readlink "/proc/${pid}/exe" 2>/dev/null)" == "${path}" ]] &&
      grep -qzxF "XDG_DATA_HOME=${RUN_ROOT}/${id}/xdg/data" "/proc/${pid}/environ" 2>/dev/null
  else
    tr '\0' '\n' <"/proc/${pid}/cmdline" 2>/dev/null | grep -qxF "${path}"
  fi
}

stop() {
  local pid="$1" i
  kill -TERM "${pid}" 2>/dev/null || return 0
  for ((i = 0; i < 50; i++)); do
    running "${pid}" || return 0
    sleep 0.1
  done
  kill -KILL "${pid}" 2>/dev/null || true
}

# Godot processes below a recorded wrapper (xvfb-run, tools/verify.sh).
godot_descendants() {
  local child
  for child in $(ps -o pid= --ppid "$1" 2>/dev/null); do
    godot_descendants "${child}"
    [[ "$(readlink "/proc/${child}/exe" 2>/dev/null)" == "${GODOT_EXE}" ]] && echo "${child}"
  done
  return 0
}

if [[ -f "${PIDS}" ]]; then
  run_find_godot cleanup
  # Games first, so a wrapper sees its child exit and tidies up after itself
  # (xvfb-run stops its Xvfb); then the wrappers and anything left below them.
  for pass in godot wrapper; do
    while read -r pid kind id path; do
      [[ -z "${pid}" ]] && continue
      [[ "${pass}" == godot ]] && [[ "${kind}" != godot ]] && continue
      [[ "${pass}" == wrapper ]] && [[ "${kind}" == godot ]] && continue
      if ! is_launched "${pid}" "${kind}" "${id}" "${path}"; then
        running "${pid}" && echo "cleanup: left ${pid} alone: it is not the ${kind} launched by run ${id}"
        continue
      fi
      if [[ "${pass}" == wrapper ]]; then
        for child in $(godot_descendants "${pid}"); do
          stop "${child}"
          echo "cleanup: stopped ${child} (godot under ${kind} ${pid})"
        done
        sleep 0.5
        running "${pid}" || { echo "cleanup: ${pid} (${kind}, run ${id}) exited"; continue; }
      fi
      stop "${pid}"
      echo "cleanup: stopped ${pid} (${kind}, run ${id})"
    done <"${PIDS}"
  done
fi
rm -rf "${RUN_ROOT}"
echo "cleanup: removed .run/; artifacts/ kept"
