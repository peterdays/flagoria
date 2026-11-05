#!/usr/bin/env bash
# Read-only lint of the feature map against the repo, no Godot needed:
#   - every features/*.md is linked from features/README.md, and every link resolves;
#   - every feature file (except README) has exactly one Drive: line:
#       Drive: drives/<path>.gd   (file must exist under the skill)
#       Drive: not player-facing
#   - every test name a feature file cites (`test_<name>`) is a registered test;
#   - every registered test is cited by at least one feature file.
#   - with --gameplay and --changed-files <path>: a gameplay PR fails when a
#     changed or added features/*.md (not README) lacks a Drive: line.
# Registered tests are the `func _test_<name>` functions in tests/run_tests.gd
# and tests/**/test_*.gd, the set `run_tests.gd -- --list` prints.
# Exit 0 when clean, 1 with one line per problem. --self-test exits 0/1 on its own.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"
SKILL=".cursor/skills/verify-flagoria"
MAP="${SKILL}/features"
DRIVES="${SKILL}/drives"
bad=0
problem() { echo "check-map: $*"; bad=1; }

CHANGED_FILE=""
GAMEPLAY=0
SELF_TEST=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --changed-files) CHANGED_FILE="${2:-}"; shift 2 ;;
    --gameplay) GAMEPLAY=1; shift ;;
    --self-test) SELF_TEST=1; shift ;;
    -h|--help)
      echo "usage: check-map.sh [--gameplay --changed-files paths.txt] [--self-test]" >&2
      exit 2 ;;
    *) echo "check-map: unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Returns the Drive: value (drives/...gd or "not player-facing") or empty.
drive_line() {
  # Prefer a line that is exactly "Drive: …" (not nested in a bullet).
  local v
  v="$(grep -E '^Drive:[[:space:]]+' "$1" | head -n 1 | sed -E 's/^Drive:[[:space:]]+//; s/[[:space:]]+$//')" || true
  printf '%s' "${v}"
}

check_drive_value() {
  # $1 = feature basename, $2 = Drive: value
  local name="$1" value="$2"
  if [[ -z "${value}" ]]; then
    problem "${name} has no Drive: line (want 'Drive: drives/<name>.gd' or 'Drive: not player-facing')"
    return
  fi
  if [[ "${value}" == "not player-facing" ]]; then
    return
  fi
  if [[ "${value}" =~ ^drives/[A-Za-z0-9_./-]+\.gd$ ]]; then
    if [[ ! -f "${SKILL}/${value}" ]]; then
      problem "${name} Drive: ${value} but ${SKILL}/${value} does not exist"
    fi
    return
  fi
  problem "${name} Drive: '${value}' is not 'drives/<path>.gd' or 'not player-facing'"
}

check_feature_drives() {
  local f name value
  for f in "${MAP}"/*.md; do
    name="$(basename "$f")"
    [[ "$name" == README.md ]] && continue
    value="$(drive_line "$f")"
    check_drive_value "${name}" "${value}"
    # A drive that covers a feature must take at least one snapshot (screen proof).
    if [[ "${value}" == drives/* ]]; then
      if ! grep -qE 'snapshot\("' "${SKILL}/${value}"; then
        problem "${name} Drive: ${value} never calls snapshot(\"…\")"
      fi
    fi
  done
}

check_index() {
  local f name link
  for f in "${MAP}"/*.md; do
    name="$(basename "$f")"
    [[ "$name" == README.md ]] && continue
    grep -q "(./${name})" "${MAP}/README.md" || problem "${name} is not linked from features/README.md"
  done
  while read -r link; do
    [[ -f "${MAP}/${link}" ]] || problem "features/README.md links ${link}, which does not exist"
  done < <(grep -o '(\./[^)]*\.md)' "${MAP}/README.md" | sed 's/^(\.\///; s/)$//')
}

check_tests() {
  local registered cited t n
  registered="$(find tests -name 'test_*.gd' -o -name run_tests.gd | sort \
    | xargs sed -n 's/^func _test_\([A-Za-z0-9_]*\)(.*/\1/p' | sort -u)"
  cited="$(cat "${MAP}"/*.md | grep -oE 'test_[A-Za-z0-9_]+(\.gd|\*)?' \
    | grep -vE '(\.gd|\*)$' | sed 's/^test_//; s/_$//' | sort -u)"
  while read -r t; do
    [[ -z "$t" ]] && continue
    grep -qxF "$t" <<<"${registered}" || problem "test_${t} is cited but no tests/ file defines _test_${t}"
  done <<<"${cited}"
  while read -r t; do
    grep -qxF "$t" <<<"${cited}" || problem "_test_${t} is not cited by any feature file"
  done <<<"${registered}"
  n="$(wc -l <<<"${registered}")"
  if [[ ${bad} -eq 0 ]]; then
    echo "check-map: OK (${n} tests, every one cited; every feature file indexed; every feature has a Drive: line)"
  fi
}

# Gameplay PR: every changed/added feature file must carry a Drive: line.
check_changed_gameplay() {
  local path name value
  [[ -n "${CHANGED_FILE}" && -f "${CHANGED_FILE}" ]] || {
    problem "--gameplay needs --changed-files pointing at an existing paths list"
    return
  }
  while read -r path; do
    [[ -z "${path}" ]] && continue
    case "${path}" in
      .cursor/skills/verify-flagoria/features/*.md) ;;
      *) continue ;;
    esac
    name="$(basename "${path}")"
    [[ "${name}" == README.md ]] && continue
    if [[ ! -f "${path}" ]]; then
      # Deleted feature file: nothing to require.
      continue
    fi
    value="$(drive_line "${path}")"
    if [[ -z "${value}" ]]; then
      problem "gameplay PR: changed feature ${name} lacks a Drive: line"
    else
      check_drive_value "${name}" "${value}"
    fi
  done < "${CHANGED_FILE}"
}

self_test() {
  local tmp failed=0
  tmp="$(mktemp -d)"
  cleanup() { rm -rf "${tmp}"; }
  trap cleanup EXIT

  mkdir -p "${tmp}/skill/features" "${tmp}/skill/drives" "${tmp}/repo/tests"
  # Minimal registered test so the test-citation loop is exercised in isolation
  # only when we invoke the real script; here we unit-test helpers via a nested run.
  cat > "${tmp}/skill/drives/ok.gd" <<'GD'
extends RefCounted
func run() -> void:
	await snapshot("start")
GD
  # Good feature
  printf '%s\n' '# Good' '' 'Drive: drives/ok.gd' '' 'See test_dummy.' > "${tmp}/skill/features/good.md"
  # Missing Drive
  printf '%s\n' '# Bad' '' 'No drive here.' > "${tmp}/skill/features/missing.md"
  # Bad value
  printf '%s\n' '# Badval' '' 'Drive: drives/nope.gd' > "${tmp}/skill/features/badval.md"
  # not player-facing is fine
  printf '%s\n' '# Npf' '' 'Drive: not player-facing' > "${tmp}/skill/features/npf.md"
  # Drive without snapshot
  printf '%s\n' 'extends RefCounted' 'func run() -> void:' '	pass' > "${tmp}/skill/drives/nosnap.gd"
  printf '%s\n' '# Nosnap' '' 'Drive: drives/nosnap.gd' > "${tmp}/skill/features/nosnap.md"

  # Run the Drive: checks by pointing SKILL/MAP at the temp tree via a subshell
  # that sources the same functions. Re-exec this script's checker against tmp
  # by copying a tiny driver.
  cat > "${tmp}/run.sh" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
SKILL="$1"
MAP="${SKILL}/features"
bad=0
problem() { echo "check-map: $*"; bad=1; }
drive_line() {
  local v
  v="$(grep -E '^Drive:[[:space:]]+' "$1" | head -n 1 | sed -E 's/^Drive:[[:space:]]+//; s/[[:space:]]+$//')" || true
  printf '%s' "${v}"
}
check_drive_value() {
  local name="$1" value="$2"
  if [[ -z "${value}" ]]; then
    problem "${name} has no Drive: line (want 'Drive: drives/<name>.gd' or 'Drive: not player-facing')"
    return
  fi
  if [[ "${value}" == "not player-facing" ]]; then return; fi
  if [[ "${value}" =~ ^drives/[A-Za-z0-9_./-]+\.gd$ ]]; then
    if [[ ! -f "${SKILL}/${value}" ]]; then
      problem "${name} Drive: ${value} but ${SKILL}/${value} does not exist"
    fi
    return
  fi
  problem "${name} Drive: '${value}' is not 'drives/<path>.gd' or 'not player-facing'"
}
for f in "${MAP}"/*.md; do
  name="$(basename "$f")"
  value="$(drive_line "$f")"
  check_drive_value "${name}" "${value}"
  if [[ "${value}" == drives/* ]] && ! grep -qE 'snapshot\("' "${SKILL}/${value}"; then
    problem "${name} Drive: ${value} never calls snapshot(\"…\")"
  fi
done
# Gameplay changed-files path
if [[ -n "${2:-}" ]]; then
  while read -r path; do
    [[ -z "${path}" ]] && continue
    name="$(basename "${path}")"
    [[ "${name}" == README.md ]] && continue
    value="$(drive_line "${SKILL}/features/${name}")"
    if [[ -z "${value}" ]]; then
      problem "gameplay PR: changed feature ${name} lacks a Drive: line"
    fi
  done < "$2"
fi
exit "${bad}"
INNER
  chmod +x "${tmp}/run.sh"

  expect_fail() {
    local label="$1"; shift
    if "$@" >"${tmp}/out" 2>&1; then
      echo "FAIL ${label}: expected non-zero"; cat "${tmp}/out"; failed=1
    else
      echo "ok   ${label}"
    fi
  }
  expect_ok() {
    local label="$1"; shift
    if "$@" >"${tmp}/out" 2>&1; then
      echo "ok   ${label}"
    else
      echo "FAIL ${label}: expected zero"; cat "${tmp}/out"; failed=1
    fi
  }

  # Full temp map has missing/bad/nosnap → must fail
  expect_fail "temp map with missing Drive" "${tmp}/run.sh" "${tmp}/skill"

  # Only good + npf → ok
  rm -f "${tmp}/skill/features/missing.md" "${tmp}/skill/features/badval.md" "${tmp}/skill/features/nosnap.md"
  expect_ok "good + not player-facing" "${tmp}/run.sh" "${tmp}/skill"

  # Gameplay PR: changed feature without Drive
  printf '%s\n' '# X' '' 'nope' > "${tmp}/skill/features/changed.md"
  printf '%s\n' '.cursor/skills/verify-flagoria/features/changed.md' > "${tmp}/changed.txt"
  # Put changed.md next to good; run.sh reads SKILL/features/<basename>
  expect_fail "gameplay changed feature lacks Drive" "${tmp}/run.sh" "${tmp}/skill" "${tmp}/changed.txt"

  # Real repo lint must pass (Drive lines already added)
  expect_ok "real feature map" bash -c "cd '${ROOT}' && '${ROOT}/${SKILL}/bin/check-map.sh'"

  trap - EXIT
  cleanup
  if [[ ${failed} -ne 0 ]]; then
    echo "check-map --self-test: FAILED"
    exit 1
  fi
  echo "check-map --self-test: OK"
  exit 0
}

if [[ ${SELF_TEST} -eq 1 ]]; then
  self_test
fi

check_feature_drives
check_index
if [[ ${GAMEPLAY} -eq 1 ]]; then
  check_changed_gameplay
fi
check_tests
exit "${bad}"
