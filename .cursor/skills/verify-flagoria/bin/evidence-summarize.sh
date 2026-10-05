#!/usr/bin/env bash
# Write artifacts/e2e-summary.txt from the latest verify (and optional screenshot) logs.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"
ART=".cursor/skills/verify-flagoria/artifacts"
mkdir -p "$ART"
sum="${ART}/e2e-summary.txt"
{
  echo "Flagoria verification evidence summary"
  echo "generated_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  if [[ -f "${ART}/verify.log" ]]; then
    echo "## tools/verify.sh"
    if grep -q 'Verification passed.' "${ART}/verify.log"; then
      echo "result=pass"
    else
      echo "result=fail"
    fi
    grep -E 'PASS |FAIL |All tests|Tests:|Verification passed|map characterization|test_smoke|test_map' "${ART}/verify.log" | sed 's/^/  /' || true
  else
    echo "## tools/verify.sh"
    echo "result=missing_log"
  fi
  echo
  echo "## Map Settings screenshot"
  if [[ -f "${ART}/out/map_settings.png" ]]; then
    echo "result=present file=out/map_settings.png"
  else
    echo "result=absent"
  fi
  echo
  echo "## Notes"
  echo "- Two-player Host/Join is not proven by verify.sh alone (see features/two-player-host-join.md)."
  echo "- Issue #45 (automated two-player smoke) and #48 (CLI map renders) are placeholders."
} >"${sum}"
echo "evidence-summarize: wrote ${sum}"
cat "${sum}"
