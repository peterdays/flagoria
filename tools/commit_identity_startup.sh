#!/bin/sh
# Proposed private startup. Nothing in the saved environment calls this.
# Writing a git config file does not install an include and is not a waited
# gate. The script exits non-zero even after a successful write so it cannot
# be read as enforcement. It does not print the address.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CONFIG=${FLAGORIA_COMMIT_IDENTITY_GITCONFIG:-}
REPO=${FLAGORIA_COMMIT_IDENTITY_REPO:-$ROOT}
if [ -z "$CONFIG" ]; then
  echo "commit-identity: git config destination is not set" >&2
  exit 1
fi

python3 "$ROOT/tools/commit_identity.py" configure-git --git-config "$CONFIG"
echo "commit-identity: wrote a git config file only; it is not installed as an include and nothing waits for it" >&2
python3 "$ROOT/tools/commit_identity.py" controls --repo "$REPO"
echo "commit-identity: not a waited gate" >&2
exit 2
