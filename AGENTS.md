# AGENTS.md

Guidance for automated agents and contributors working in this repository.

## Privacy rule (read before opening issues or PRs)

Never put anything about the repository owner personally into issues, comments, pull requests, commit messages, or files. That means:

- no names, and no attributions such as "X says" or "the owner wants";
- no email addresses;
- no local file paths, home directories, or machine names;
- no other personal details of any kind.

Write everything in a neutral, impersonal project voice ("the game should…", "this change adds…").

The only personal identity allowed anywhere is the git commit author metadata, using the git commit author identity already configured for commits. Do not repeat that identity in file contents, PR bodies, or issue text.

## Other house rules

- Two-player multiplayer must keep working after every change.
- Small, self-contained pull requests, one concern each. Pull requests double as documentation: focused commits and a short why/what description should let a reader understand exactly what changed and why. Never bundle several issues or features into one pull request. When work must be split, each part should stand on its own; stack pull requests only where one truly depends on another, and reference the related issue numbers.
- Pull request size:
  - One concern per pull request.
  - Cap: about 1,000 changed lines of hand-written code. There is no cap on the number of files.
  - Not counted: generated files (such as `.import` files, build outputs and codegen), lockfiles, vendored code, art and sound assets, and docs.
  - Measure with `git diff --numstat origin/main...HEAD`, summing added and deleted lines of code files outside the excluded paths. Report the counted size in the description, for example `Size: ~640 code lines (excl. .import/assets)`.
  - A pull request over the cap is split along natural seams (refactor then feature; data and logic then UI). If it cannot be split, its description has a `## Why this is large` section. The reviewer judges that reason and can flag the pull request if it does not hold up.
  - Do not over-split. Splitting one concern into tiny dependent pull requests is fragmentation. Each split must be independently reviewable and mergeable.
- Nothing is merged, released, or tagged without the owner's approval.
- Run `tools/verify.sh` before opening a pull request; CI runs the same check.
- For scripted verification recipes (launch, doctor, drive, evidence), use `.cursor/skills/verify-flagoria/` when that skill is present.

## Known mistakes and the rules that prevent them

Mistakes that have cost time in this repository before. "Enforced by" says what catches each one. "Review" means nothing automatic catches it yet, so the rule is only as strong as the person following it.

| Mistake | Rule | Enforced by |
|---|---|---|
| Committing `.import` files that Godot re-saved during a run (hundreds of unrelated files in a diff) | Commit `.import` changes only when the PR is about imports. Before committing, check `git status --short -- '*.import'` and revert unrelated ones with `git checkout -- ':(glob)**/*.import'`. A project-wide re-import is its own PR. | Committed `.import` files match the current Godot defaults (#154), so a clean run makes no churn. Otherwise review. |
| Two Godot runs sharing one `user://` (settings, saves) and breaking each other | Give every run its own user dirs: separate `XDG_CONFIG_HOME`, `XDG_DATA_HOME` and `XDG_CACHE_HOME`. Work in your own `git worktree` off fresh `origin/main`, not in a checkout another task is using. | `tools/verify.sh` makes per-run temporary dirs (#155). Direct `godot` calls: review. |
| Killing another task's Godot (for example `pkill godot`) | Stop only processes this run started, by their recorded PIDs. | Review. |
| `git`/`gh` acting with a stale or wrong token because `GH_TOKEN` or `GITHUB_TOKEN` is set in the environment (push rejected, or a PR opened by the wrong account) | Run `git` and `gh` as `env -u GH_TOKEN -u GITHUB_TOKEN git …` / `… gh …` so the configured login is used. | Review. |
| A stacked PR still showing its parent's commits, or still targeting the parent branch, after the parent merged | After the parent merges: `gh pr edit <child> --base main`, then on the child branch `git fetch origin && git merge origin/main`, resolve, and push. Merged branches are not deleted automatically here, so GitHub does not retarget the child for you. Say in the child's description which PR it stacks on. | Review. |
| Rebasing a branch with an open PR and force-pushing it (review threads lose context, other worktrees break) | Bring the branch up to date by merging `origin/main` into it and pushing normally. Force-push only with the maintainer's approval (see below). | Review. |
| A PR that leaks an email address, a local path or an attribution, or that runs far over the size cap without saying why | Follow the privacy rule and the size rule above, and fill in `.github/pull_request_template.md` (including the `Size:` line). Run `python3 tools/pr_hygiene.py --base origin/main --title "…" --body-file body.md` before opening the PR. False positive: add an entry to `.github/pr-hygiene-allow.txt` (format in the header of `tools/pr_hygiene.py`). | The `pr-hygiene` workflow fails on email addresses, local paths, and over-cap PRs with no `## Why this is large` section or `Size justification:` line. Attribution phrases, the PR author's login and a missing `Size:` line are warnings only. Names: review. |

## Human in the loop

Agents do not take irreversible project actions on their own. The maintainer approves merges and other high-impact steps.

- Never merge, deploy, change secrets or permissions, or run destructive git commands (force-push to shared branches, history rewrites, branch deletion, hard resets of others' work) without the maintainer's approval.
- Opening pull requests, filing issues, and commenting are fine.
- Merges happen only through the maintainer's pipeline: CI green, Play Sentinel PASS (the project's gameplay and usability review), and review threads resolved.

Related: the privacy rule above, and the small-PR and verify notes under Other house rules.
