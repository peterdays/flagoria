#!/usr/bin/env bash
# Print the next Android test pre-release tag: v<next-minor>-test.<N>.
#
# Takes the highest vX.Y.Z tag (pre-release tags excluded), bumps the minor
# (v1.3.1 -> v1.4.0), and sets N to 1 + the highest existing v1.4.0-test.N.
# Reads tag names from stdin, one per line, so it can run on any list:
#   git tag -l | ./tools/next_test_tag.sh
set -euo pipefail

tags="$(cat)"
base="$(printf '%s\n' "$tags" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1 || true)"
if [[ -z "$base" ]]; then
  base="v0.0.0"
fi
IFS=. read -r major minor _ <<<"${base#v}"
next="v${major}.$((minor + 1)).0"
last="$(printf '%s\n' "$tags" | grep -E "^${next//./\\.}-test\\.[0-9]+$" | sed 's/.*-test\.//' | sort -n | tail -n 1 || true)"
echo "${next}-test.$(( ${last:-0} + 1 ))"
