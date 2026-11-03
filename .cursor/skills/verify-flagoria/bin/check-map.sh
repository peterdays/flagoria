#!/usr/bin/env bash
# Read-only lint of the feature map against the repo, no Godot needed:
#   - every features/*.md is linked from features/README.md, and every link resolves;
#   - every test name a feature file cites (`test_<name>`) is a registered test;
#   - every registered test is cited by at least one feature file.
# Registered tests are the `func _test_<name>` functions in tests/run_tests.gd
# and tests/**/test_*.gd, the set `run_tests.gd -- --list` prints.
# Exit 0 when clean, 1 with one line per problem.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"
MAP=".cursor/skills/verify-flagoria/features"
bad=0
problem() { echo "check-map: $*"; bad=1; }

for f in "${MAP}"/*.md; do
  name="$(basename "$f")"
  [[ "$name" == README.md ]] && continue
  grep -q "(./${name})" "${MAP}/README.md" || problem "${name} is not linked from features/README.md"
done
while read -r link; do
  [[ -f "${MAP}/${link}" ]] || problem "features/README.md links ${link}, which does not exist"
done < <(grep -o '(\./[^)]*\.md)' "${MAP}/README.md" | sed 's/^(\.\///; s/)$//')

registered="$(find tests -name 'test_*.gd' -o -name run_tests.gd | sort \
  | xargs sed -n 's/^func _test_\([A-Za-z0-9_]*\)(.*/\1/p' | sort -u)"
# Test names cited in the map; file names (test_x.gd) and globs (test_x_*) are not names.
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
  echo "check-map: OK (${n} tests, every one cited; every feature file indexed)"
fi
exit "${bad}"
