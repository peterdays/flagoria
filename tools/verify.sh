#!/usr/bin/env bash
# Headless check: this Godot 4.1 project imports, opens, and every GDScript parses.
#
# Confirmed against Godot 4.1.4 --help:
#   --headless, --editor, --quit, and --check-only (only with --script) exist.
#   --import does not (that flag arrived in a later 4.x release).
# --editor --quit exits 0 even when a script fails to parse, and shutdown prints
# benign RID-leak ERROR lines. This script treats those leaks as non-fatal and
# fails on parse/load errors instead.
#
# Usage:
#   ./tools/verify.sh
#   GODOT=/path/to/Godot_v4.1.x_linux.x86_64 ./tools/verify.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GODOT="${GODOT:-godot}"

if [[ ! -x "$GODOT" ]] && ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "error: Godot 4.1 editor binary not found (set GODOT to the binary path)" >&2
  exit 127
fi

version="$("$GODOT" --version)"
echo "Godot version: ${version}"
case "${version}" in
  4.1.*) ;;
  *)
    echo "error: project.godot targets Godot 4.1. Refusing to run ${version}; a newer editor can migrate the project." >&2
    exit 1
    ;;
esac

# Real failures. RID leak lines from headless editor shutdown are not included.
log_has_project_error() {
  grep -E -q 'SCRIPT ERROR:|Parse [Ee]rror|Failed to load script|Failed loading resource' "$1"
}

run_editor() {
  local log="$1"
  local status
  set +e
  "$GODOT" --headless --path "$ROOT" --editor --quit >"${log}" 2>&1
  status=$?
  set -e
  cat "${log}"
  return "${status}"
}

echo "== Import project (Godot 4.1: --headless --editor --quit) =="
import_log="$(mktemp)"
if ! run_editor "${import_log}"; then
  echo "error: Godot editor exited non-zero during import" >&2
  rm -f "${import_log}"
  exit 1
fi
rm -f "${import_log}"

echo "== Load project again, after resources have been imported =="
load_log="$(mktemp)"
load_status=0
run_editor "${load_log}" || load_status=$?

# The first open can preload an editor-plugin icon before its .ctex exists.
# Files are on disk when that process exits; only a later open is the load check.
# One extra open if that specific "not imported yet" message is still present.
if [[ "${load_status}" -eq 0 ]] && log_has_project_error "${load_log}" \
  && grep -q 'Make sure resources have been imported' "${load_log}"; then
  echo "== Import still incomplete; opening the project once more =="
  load_status=0
  run_editor "${load_log}" || load_status=$?
fi

if [[ "${load_status}" -ne 0 ]] || log_has_project_error "${load_log}"; then
  echo "error: project failed to load cleanly" >&2
  rm -f "${load_log}"
  exit 1
fi
rm -f "${load_log}"
echo "Project load: ok"

echo "== Parse GDScript (--check-only, one file at a time) =="
fail=0
found=0
while IFS= read -r f; do
  found=1
  rel="res://${f#./}"
  echo "-- ${rel}"
  slog="$(mktemp)"
  set +e
  "$GODOT" --headless --path "$ROOT" --check-only --script "${rel}" >"${slog}" 2>&1
  status=$?
  set -e
  cat "${slog}"
  if [[ "${status}" -ne 0 ]] || log_has_project_error "${slog}"; then
    echo "error: parse failed for ${rel} (exit ${status})" >&2
    fail=1
  fi
  rm -f "${slog}"
done < <(find . -type f -name '*.gd' -not -path './.git/*' -not -path './.godot/*' | sort)

if [[ "${found}" -eq 0 ]]; then
  echo "error: no GDScript files found" >&2
  exit 1
fi
if [[ "${fail}" -ne 0 ]]; then
  exit 1
fi

echo "Script parse: ok"
echo "Verification passed."
