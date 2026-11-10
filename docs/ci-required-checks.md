# Required CI check names

Branch protection lists four required checks by their **job display name** (the workflow `jobs.<id>.name` field, not the workflow file name). Those names must stay in sync with `.github/workflows/*.yml` and with the committed list in [`.github/required-checks.txt`](../.github/required-checks.txt).

## Local check

```bash
python3 tools/required_checks.py
```

`tools/verify.sh` and the **Privacy and size check** workflow run this before heavier work. The script finishes in about one second.

## Renaming a required job

1. Change the job `name:` in the workflow YAML.
2. Update the matching line in `.github/required-checks.txt` (workflow file, job id, display name).
3. Update branch protection on GitHub so the required check uses the new display name. The in-repo script does not call the GitHub API.

## Current mappings

See `.github/required-checks.txt` for the canonical list enforced in CI.
