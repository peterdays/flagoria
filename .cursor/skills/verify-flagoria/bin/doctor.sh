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
if [[ -z "${GODOT:-}" ]]; then
  echo "doctor: GODOT is unset" >&2
  ok=0
elif [[ ! -x "$GODOT" ]] && ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "doctor: GODOT not executable: (set GODOT to the Godot ${want:-editor} binary)" >&2
  ok=0
else
  ver="$("$GODOT" --version 2>/dev/null || true)"
  echo "doctor: GODOT version=${ver} (project.godot wants ${want:-unknown}.x)"
  if [[ -z "${want}" || "${ver}" != "${want}".* ]]; then
    echo "doctor: need Godot ${want:-?}.x, got ${ver}" >&2
    ok=0
  fi
fi

if grep -q 'test_map_characterization' tests/run_tests.gd 2>/dev/null; then
  echo "doctor: map characterization test present in tests/run_tests.gd"
else
  echo "doctor: map characterization test missing from tests/run_tests.gd" >&2
  ok=0
fi

if [[ "${ok}" -ne 1 ]]; then
  exit 1
fi
echo "doctor: repo root OK (project.godot + tools/verify.sh + tests/run_tests.gd)"
echo "doctor: OK"
