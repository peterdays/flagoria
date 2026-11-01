#!/usr/bin/env bash
# Read-only: is this Flagoria checkout worth driving?
#   doctor.sh                    checks the checkout
#   doctor.sh --instance <run>   also checks a game started by launch.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"
# shellcheck source=run_lib.sh
source "${ROOT}/.cursor/skills/verify-flagoria/bin/run_lib.sh"

instance=""
case "${1:-}" in
  "") ;;
  --instance)
    instance="${2:-}"
    if [[ -z "${instance}" || "${instance}" == */* || "${instance}" == .* ]]; then
      echo "usage: doctor.sh [--instance <run-id>]" >&2
      exit 2
    fi
    ;;
  *) echo "usage: doctor.sh [--instance <run-id>]" >&2; exit 2 ;;
esac

ok=1
if [[ ! -f project.godot ]]; then
  echo "doctor: missing project.godot (not repo root?)" >&2
  ok=0
fi
if [[ ! -f tools/verify.sh ]]; then
  echo "doctor: missing tools/verify.sh" >&2
  ok=0
fi
if [[ ! -f tests/run_tests.gd ]]; then
  echo "doctor: missing tests/run_tests.gd" >&2
  ok=0
fi
# Expected engine major.minor comes from project.godot (config/features), so
# this check follows the project when it moves to a new Godot version.
want=""
if [[ -f project.godot ]]; then
  want="$(sed -n 's/^config\/features=PackedStringArray(\(.*\))$/\1/p' project.godot \
    | tr ',' '\n' | tr -d ' "' | grep -E '^[0-9]+\.[0-9]+$' | head -n 1 || true)"
  if [[ -z "${want}" ]]; then
    echo "doctor: no engine version in project.godot config/features" >&2
    ok=0
  fi
fi
# Same lookup as tools/verify.sh: GODOT if set, else `godot` on PATH.
GODOT="${GODOT:-godot}"
if [[ ! -x "$GODOT" ]] && ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "doctor: Godot not found: ${GODOT} (put godot on PATH or set GODOT to the Godot ${want:-editor} binary)" >&2
  ok=0
else
  ver="$("$GODOT" --version 2>/dev/null || true)"
  echo "doctor: GODOT version=${ver} (project.godot wants ${want:-unknown}.x)"
  if [[ -z "${want}" || "${ver}" != "${want}".* ]]; then
    echo "doctor: need Godot ${want:-?}.x, got ${ver}" >&2
    ok=0
  fi
fi

if grep -q 'test_map_characterization' tests/world/test_map_characterization.gd 2>/dev/null; then
  echo "doctor: map characterization test present in tests/world/test_map_characterization.gd"
else
  echo "doctor: map characterization test missing from tests/world/test_map_characterization.gd" >&2
  ok=0
fi

if [[ "${ok}" -eq 1 ]]; then
  echo "doctor: repo root OK (project.godot + tools/verify.sh + tests/run_tests.gd)"
fi

# Prints one line per check of a launched instance; clears ok on a failure.
check() {  # check <ok 0|1> <message>
  if [[ "$1" -eq 1 ]]; then
    echo "doctor: instance ok: $2"
  else
    echo "doctor: instance FAIL: $2" >&2
    ok=0
  fi
}

running() {  # alive and not a zombie
  [[ -r "/proc/$1/stat" ]] && [[ "$(awk '{print $3}' "/proc/$1/stat" 2>/dev/null)" != Z ]]
}

# Every check only reads .run/ and /proc; nothing is written or sent.
if [[ -n "${instance}" ]]; then
  run_dir="${RUN_ROOT}/${instance}"
  godots=0
  while read -r pid kind id path; do
    [[ "${id}" == "${instance}" ]] || continue
    if ! running "${pid}"; then
      check 0 "pid ${pid} (${kind}) has exited"
      continue
    fi
    check 1 "pid ${pid} (${kind}) is running"
    [[ "${kind}" == godot ]] || continue
    godots=$((godots + 1))
    exe="$(readlink "/proc/${pid}/exe" 2>/dev/null || true)"
    if [[ "${exe}" != "${path}" ]]; then
      check 0 "pid ${pid} runs ${exe:-?}, not the recorded Godot ${path}"
      continue
    fi
    # Only the recorded Godot binary is run, never an unknown exe.
    ver="$("${exe}" --version 2>/dev/null || true)"
    if [[ -n "${want}" && "${ver}" == "${want}".* ]]; then
      check 1 "pid ${pid} is Godot ${ver}"
    else
      check 0 "pid ${pid} is Godot ${ver:-?}, project.godot wants ${want:-?}.x"
    fi
    data="$(tr '\0' '\n' <"/proc/${pid}/environ" 2>/dev/null | sed -n 's/^XDG_DATA_HOME=//p' || true)"
    if [[ "${data}" == "${run_dir}/xdg/"* ]]; then
      check 1 "pid ${pid} XDG_DATA_HOME is in .run/${instance}/xdg/"
    else
      check 0 "pid ${pid} XDG_DATA_HOME=${data:-unset} is not in .run/${instance}/xdg/ (it may share a real user://)"
    fi
  done < <(cat "${PIDS}" 2>/dev/null || true)
  [[ "${godots}" -gt 0 ]] || check 0 "no running Godot recorded for run ${instance} in .run/pids"

  log="${run_dir}/game.log"
  ready="$(grep -n -m 1 '^VERIFY_READY ' "${log}" 2>/dev/null | cut -d: -f1 || true)"
  if [[ -z "${ready}" ]]; then
    check 0 "no VERIFY_READY line in .run/${instance}/game.log"
  else
    check 1 "VERIFY_READY on line ${ready} of game.log"
    bad="$(tail -n "+${ready}" "${log}" | grep -m 1 -E 'SCRIPT ERROR|Node not found' || true)"
    if [[ -z "${bad}" ]]; then
      check 1 "no SCRIPT ERROR or Node not found after VERIFY_READY"
    else
      check 0 "game.log after VERIFY_READY: ${bad}"
    fi
  fi
fi

if [[ "${ok}" -ne 1 ]]; then
  echo "doctor: FAIL${instance:+ (relaunch; do not retry the step)}" >&2
  exit 1
fi
echo "doctor: OK${instance:+ (instance ${instance})}"
