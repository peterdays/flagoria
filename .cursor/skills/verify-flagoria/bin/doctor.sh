#!/usr/bin/env bash
# Read-only: is this Flagoria checkout worth driving?
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"

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
if [[ -z "${GODOT:-}" ]]; then
  echo "doctor: GODOT is unset" >&2
  ok=0
elif [[ ! -x "$GODOT" ]] && ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "doctor: GODOT not executable: (set GODOT to the 4.1 editor binary)" >&2
  ok=0
else
  ver="$("$GODOT" --version 2>/dev/null || true)"
  echo "doctor: GODOT version=${ver}"
  case "${ver}" in
    4.1.*) ;;
    *)
      echo "doctor: need Godot 4.1.x, got ${ver}" >&2
      ok=0
      ;;
  esac
fi

echo "doctor: repo root OK (project.godot + tools/verify.sh)"
if grep -q 'test_map_characterization' tests/run_tests.gd 2>/dev/null; then
  echo "doctor: map characterization test present in tests/run_tests.gd"
else
  echo "doctor: map characterization test not in this checkout (smoke-only runner)"
fi

if [[ "${ok}" -ne 1 ]]; then
  exit 1
fi
echo "doctor: OK"
