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

## New issue format

Every new issue has a concise native GitHub title and these three body sections, in this order:

### What it does

State the intended change or tracking purpose in one sentence.

### Scope

Describe one concern. State what is included and what is out of scope. Link related issues instead of copying their scope.

### Done when

List executable completion checks. Each check identifies an actor, an action, and an observable pass condition. Avoid criteria such as "works correctly" without a defined result.

Use the task issue form when available. Issues created through the API, CLI, or any other route must use the same native title and body sections.

This format applies to all new issues, including roadmap and epic trackers. A new tracker links its tasks and defines completion as acceptance of the included tasks, with deferred scope stated explicitly.

Do not automatically rewrite historical issues to match this format.

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
- CI time is weighed, not capped. Each new test, verify step or CI job states its expected time cost in the pull request (template line "Time cost"). Every pull request workflow ends with a "Job times" job (`tools/ci_job_times.py`) whose job summary shows each job's time against the median of recent successful main runs; a job over 5 minutes gets a warning, never a failure.
- Where code goes: [docs/architecture.md](docs/architecture.md) maps every script to its module and its target folder, and says where new scripts, data, tests and tools go.
- For scripted verification recipes (launch, doctor, drive, evidence), use `.cursor/skills/verify-flagoria/` when that skill is present. The feature map under that skill is the index of what to open and drive.
- Agent context budget (deterministic): start from `.cursor/skills/verify-flagoria/brief.template.md`, fill only its fields, and keep the brief under the caps enforced by `python3 tools/agent_budget.py check-brief FILE`. Before Ready, write a receipt and run `python3 tools/agent_budget.py check-receipt FILE --brief BRIEF`. PR bodies must keep the `Verify: once` and `Drive: …` lines; `tools/pr_hygiene.py` fails without them. Never `find`/`curl` Godot mid-task; run `./tools/ensure_godot.sh` once if doctor says it is missing.
- Every new player-facing mechanic (a new choppable, a tower, a wall type, a city rule) adds its feature file `.cursor/skills/verify-flagoria/features/<feature>.md` and its index line in `features/README.md` in the same pull request. It also adds a drive under `.cursor/skills/verify-flagoria/drives/` when a player can reach the feature in a running game. Before each checkpoint in #253's gate, a verification maintenance pass checks the skill against the game. The rule and the pass are described in [docs/architecture.md](docs/architecture.md#rules).
- Before a pull request is Ready: run that feature's drive locally under xvfb (`./.cursor/skills/verify-flagoria/bin/launch.sh drives/<name>.gd --display`, using the feature file's `Drive:` line), compare the screenshots to the screens the feature file promises, fix mismatches, and attach the screenshots on the pull request (or point at the CI `drive-screenshots` artifact). Pull requests that are not player-facing skip the drive and say so under Feature file. Record the one-pass Verify/Drive receipt lines in the PR body.
- Merges require these four checks to pass on the current pull request head: `Load project and parse scripts`, `Privacy and size check`, `Netcode stress`, and `Gameplay drives`. Review threads must be resolved. Gameplay pull requests also require the contributor's own feature drive run and reviewed screenshot evidence, as described above. These requirements do not replace the approval rules under Human in the loop.
- Roadmap and epic trackers follow [docs/issue-trackers.md](docs/issue-trackers.md).

## Known mistakes and the rules that prevent them

Mistakes that have cost time in this repository before. "Enforced by" says what catches each one. "Review" means nothing automatic catches it yet, so the rule is only as strong as the person following it.

| Mistake | Rule | Enforced by |
|---|---|---|
| Mid-task `find`/`curl`/`unzip` of Godot (minutes of shell thrash every gameplay agent) | Godot must already be on `PATH` (or `GODOT`). If doctor says it is missing, run `./tools/ensure_godot.sh` once, then continue. Never download Godot inside a feature implement loop. Cloud environments bake that install into the environment `install` script. | `doctor.sh` points at `tools/ensure_godot.sh`. Review for ad-hoc downloads. |
| Tool-result floods from broad greps, repeated reads, and stacked verify/drive loops | Use the fixed brief/receipt schema (`tools/agent_budget.py`). Feature map path in the brief, discovery capped at 10, one verify and one drive before Ready. | `agent_budget.py` and `pr_hygiene.py` (Verify/Drive lines). Mid-task search thrash: review. |
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
- Merges happen only through the maintainer's pipeline and require approval or an existing standing permission that covers the specific merge. These four checks must pass on the current pull request head: `Load project and parse scripts`, `Privacy and size check`, `Netcode stress`, and `Gameplay drives`. Review threads must be resolved. For gameplay changes, the contributor runs the relevant feature drive, reviews its screenshots against the feature's expected behavior, and attaches or links the evidence before marking the pull request Ready.
- The optional gameplay and usability advisor provides advice only. Its approval is not a QA or merge gate. Contributors remain responsible for verification and evidence. Passing checks or receiving advice grants no merge, release, deployment, or other approval authority.

Related: the privacy rule above, and the small-PR and verify notes under Other house rules.
