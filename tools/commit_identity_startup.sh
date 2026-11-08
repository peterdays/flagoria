#!/bin/sh
# Proposed private startup. Nothing in the saved environment calls this.
# The address is taken from FLAGORIA_COMMIT_IDENTITY_EMAIL. This script does
# not print it, does not invent a noreply or platform address, and does not
# disable hooks. A hook scan is not acceptance of a commit; the commit object
# still has to be checked after it is written.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CONFIG=${FLAGORIA_COMMIT_IDENTITY_GITCONFIG:-}
REPO=${FLAGORIA_COMMIT_IDENTITY_REPO:-$ROOT}
if [ -z "$CONFIG" ]; then
  echo "commit-identity: git config destination is not set" >&2
  exit 1
fi

python3 "$ROOT/tools/commit_identity.py" configure-git --git-config "$CONFIG"
python3 "$ROOT/tools/commit_identity.py" controls --repo "$REPO"
