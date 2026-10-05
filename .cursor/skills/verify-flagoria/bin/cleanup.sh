#!/usr/bin/env bash
# Tear down PIDs recorded for this skill run. Keep artifacts/.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"
RUN=".cursor/skills/verify-flagoria/.run"
if [[ -d "${RUN}" ]]; then
  if [[ -f "${RUN}/pids" ]]; then
    while read -r pid; do
      [[ -z "${pid}" ]] && continue
      if kill -0 "${pid}" 2>/dev/null; then
        kill "${pid}" 2>/dev/null || true
        wait "${pid}" 2>/dev/null || true
      fi
    done < "${RUN}/pids"
  fi
  rm -rf "${RUN}"
fi
echo "cleanup: removed .run scratch; artifacts retained"
