#!/usr/bin/env bash
# Write artifacts/out/e2e-summary.txt (ignored) from the latest verify (and optional screenshot) logs.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"
ART=".cursor/skills/verify-flagoria/artifacts"
mkdir -p "${ART}/out"
sum="${ART}/out/e2e-summary.txt"
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
  elif [[ -f "${ART}/map_settings.png" ]]; then
    echo "result=not_captured_this_run reference=map_settings.png (run drive-map-settings-screenshot.sh to capture)"
  else
    echo "result=absent"
  fi
  echo
  echo "## Notes"
  echo "- Headless two-peer joins are proven by verify.sh; the menu Host/Join between two GUI instances is not (see features/two-player-host-join.md)."
  echo "- Issue #45 (menu Host/Join smoke) and #48 (general map renders) are partly covered; see features/README.md."
} >"${sum}"
echo "evidence-summarize: wrote ${sum}"
cat "${sum}"
