# Sourced by the bin/ helpers: run dirs, the Godot lookup and .run/pids.
# Each line of .run/pids is "<pid> <kind> <run-id> <path>". cleanup.sh stops a
# PID only while /proc/<pid> still matches: for kind "godot" the exe is <path>
# and XDG_DATA_HOME is the run's scratch dir; for "xvfb-run" and "verify"
# <path> is an argument of the command line.
SKILL="${ROOT}/.cursor/skills/verify-flagoria"
RUN_ROOT="${SKILL}/.run"
PIDS="${RUN_ROOT}/pids"
# Per-run evidence, kept through cleanup (artifacts/out/ is gitignored).
EVIDENCE_ROOT="${SKILL}/artifacts/out/runs"

# GODOT if set, else `godot` on PATH (as tools/verify.sh). GODOT_EXE is the
# resolved binary, which is what /proc/<pid>/exe shows for its processes.
run_find_godot() {
  GODOT="${GODOT:-godot}"
  local found
  found="$(command -v "$GODOT" 2>/dev/null)" || {
    echo "$1: Godot not found: ${GODOT} (put godot on PATH or set GODOT)" >&2
    exit 127
  }
  GODOT_EXE="$(readlink -f "$found")"
}

# Fresh .run/<run-id>/ for a run named after $1, with empty XDG dirs, so the
# game's user:// starts empty and never touches the real one. Exports the
# run's evidence dir as VERIFY_EVIDENCE_DIR for drive_base.gd's snapshot().
run_new() {
  RUN_ID="$1-$(date +%Y%m%d-%H%M%S)-$$"
  RUN_DIR="${RUN_ROOT}/${RUN_ID}"
  mkdir -p "${RUN_DIR}/xdg/data" "${RUN_DIR}/xdg/config" "${RUN_DIR}/xdg/cache"
  export VERIFY_EVIDENCE_DIR="${EVIDENCE_ROOT}/${RUN_ID}"
  mkdir -p "${VERIFY_EVIDENCE_DIR}"
  export XDG_DATA_HOME="${RUN_DIR}/xdg/data"
  export XDG_CONFIG_HOME="${RUN_DIR}/xdg/config"
  export XDG_CACHE_HOME="${RUN_DIR}/xdg/cache"
}

# run_record <pid> <kind> <run-id> <path>
run_record() {
  mkdir -p "${RUN_ROOT}"
  echo "$1 $2 $3 $4" >>"${PIDS}"
}

# Record the Godot processes under <pid> (for example the game xvfb-run
# starts). Waits up to 5 s for the first one to appear.
run_record_godot_children() {
  local parent="$1" id="$2" child i
  for ((i = 0; i < 50; i++)); do
    for child in $(ps -o pid= --ppid "${parent}" 2>/dev/null); do
      if [[ "$(readlink "/proc/${child}/exe" 2>/dev/null)" == "${GODOT_EXE}" ]]; then
        run_record "${child}" godot "${id}" "${GODOT_EXE}"
        return 0
      fi
    done
    sleep 0.1
  done
  return 1
}
