# AGENTS.md

Guidance for automated agents and contributors working in this repository.

## Privacy rule (read before opening issues or PRs)

Never put anything about the repository owner personally into issues, comments, pull requests, commit message prose, or files. That means:

- no names, and no attributions such as "X says" or "the owner wants";
- no email addresses;
- no local file paths, home directories, or machine names;
- no other personal details of any kind.

Write everything in a neutral, impersonal project voice ("the game should…", "this change adds…").

The git author and committer are the repo-local identity already configured for commits. A platform hook may append a `Co-authored-by`, `Made-with`, or `Generated-by` trailer; leave that trailer in the commit. Do not copy a name or address from git metadata into file contents, pull request bodies, issue text, or the rest of a commit message.

## Commit identity

Cursor agents use the trusted private repo-local identity config (`user.name` and `user.email` in this checkout's local git config) for the raw author and the raw committer. That config is the existing intended personal-provider address. Do not copy the name or address into files, issues, pull requests, or commit messages.

If that local identity is missing, stop and report a blocker. Do not substitute an agent address or a GitHub noreply address.

Run `python3 tools/commit_identity_hook.py install` in this checkout, including a fresh Cursor checkout. The check is not global and does not run until that command has been run here. Install wires a local pre-push script through the hooks path already in use: it does not change `core.hooksPath` and it does not remove other hooks. The check rejects a new outgoing commit whose raw author or committer differs from the local identity. It allows a `Co-authored-by`, `Made-with`, or `Generated-by` trailer and does not remove one. Commits already reachable from a remote-tracking ref are not rechecked.

A merge commit made by GitHub may use GitHub's committer. That committer is outside this local check. The check is not a CI gate or a security control.

## New issue format

Every new issue has a concise native GitHub title and these three body sections, in this order:

### What it does

State the intended change or tracking purpose in one sentence.

### Scope

Describe one concern. State what is included and what is out of scope. Link related issues instead of copying their scope.

Keep each issue to one shippable vertical slice. When a spec has future slices with no immediate owner, file each of them as its own issue when the parent is created, and link them, instead of leaving them as unchecked items inside the parent. Never open an issue that bundles a slice about to be delivered with unowned future slices. This keeps milestones from accumulating open scope that nobody is working on.

### Done when

List executable completion checks. Each check identifies an actor, an action, and an observable pass condition. Avoid criteria such as "works correctly" without a defined result.

Use the task issue form when available. Issues created through the API, CLI, or any other route must use the same native title and body sections, plus the triage headings under Issue triage labels.

This format applies to all new issues, including roadmap and epic trackers. A new tracker links its tasks and defines completion as acceptance of the included tasks, with deferred scope stated explicitly.

Do not automatically rewrite historical issues to match this format.

## Roadmap and issues

- Milestones are the default way to group issues. Open an umbrella or epic issue only for work that spans more than one milestone, or for dependent pieces that share one rationale (for example the weapon building-block system, or the dedicated-server epic #17). Never open an umbrella whose checklist mirrors a single milestone; the milestone already is that list.
- Close an issue when its delivered v1 slice ships. Any future slice without an owner becomes its own linked issue, filed at creation or when scope shifts, and never stays behind as an unchecked item in the parent.

## Issue triage labels

The task form collects reach, impact, confidence, effort, risk area and severity. A workflow on issue open and edit (`issue-triage`) reads those fields from the body and applies routing labels. It scores an issue only when the author login equals `SCORED_AUTHOR` in `tools/issue_triage.py`. Every other author is ignored. The workflow does not call a model or any external service.

The labels are a routing hint for bots that open pull requests. They are not an approval record. Approvals are tracked outside this repository.

`RICE = reach * impact * confidence / effort`. Reach is an integer 1 through 10, impact is one of 0.25, 0.5, 1, 2 or 3, and effort is person-weeks one of 0.25, 0.5, 1, 2 or 4. The form records confidence as 50, 80 or 100, and the scorer uses that as 0.5, 0.8 or 1. One bucket label is applied when the fields parse:

- `rice: low` when the score is below 6
- `rice: med` when the score is at least 6 and below 12
- `rice: high` when the score is 12 or more

Exactly one path label is applied:

- `triage: auto-merge` — a later pull request may auto-merge when the required checks are green.
- `triage: escalate` — an owner decision comes before merge.

Escalate when any of these is true. Otherwise the path is `triage: auto-merge`.

- A high-blast risk area is selected and severity is med or high. High-blast areas are saves/world data, netcode/multiplayer sync, release/signing/CI and security/privacy.
- Severity is high, whatever else is selected, including core input or none. Severity high is decided before the high-blast check.
- Any of the six fields is missing or is not one of the values above.

`core input` and `none` are not high-blast. Low severity does not escalate on its own, even when a high-blast area is selected. Selecting `none` together with another area still counts that other area.

`workflow_dispatch` runs the same scorer over open issues by that author. An issue whose fields do not parse gets `triage: escalate` and `triage: needs-fields`. A later open or edit that parses the fields removes `triage: needs-fields`. That dispatch is manual and is not part of pull-request CI.

The arithmetic and the path are repeated in one workflow comment, updated in place, marked `<!-- flagoria-issue-triage -->`. An issue opened outside the form can use the same headings, or a single line per field (`Reach: 5`, `Risk area: none`):

```
### Reach

5

### Impact

1

### Confidence

80

### Effort

1

### Risk area

- [x] none

### Severity

low
```

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

## Writing netcode stress scenarios

A scenario that `tools/stress_netcode.py` runs must be deterministic. Fix the world seed. Do not time it with `await _wait`, `OS.delay_msec`, or `await create_timer`. Wait until an explicit host or peer state is true, and put a bounded timeout on that wait. Each run has a time budget (`--timeout`, default 60 s). The job stops at the first run that fails: it names the scenario, the run index, and the time, and it does not finish the rest of the matrix.

One flaky run otherwise fails only after every scenario has finished, which costs about 30 minutes of CI. `tools/stress_scenario_lint.py` runs inside `tools/verify.sh` and rejects a bare sleep or an unseeded random call in a stress scenario or the probe it launches. It does not follow other helpers. Picking a free UDP port may stay random. A live screenshot drive that is not the stress run may keep a short settle; that function stays in `tools/stress_scenario_lint_allow.txt`, and new scenarios do not go on that list.

## Known mistakes and the rules that prevent them

Mistakes that have cost time in this repository before. "Enforced by" says what catches each one. "Review" means nothing automatic catches it yet, so the rule is only as strong as the person following it.

| Mistake | Rule | Enforced by |
|---|---|---|
| Mid-task `find`/`curl`/`unzip` of Godot (minutes of shell thrash every gameplay agent) | Godot must already be on `PATH` (or `GODOT`). If doctor says it is missing, run `./tools/ensure_godot.sh` once, then continue. Never download Godot inside a feature implement loop. Cloud environments bake that install into the environment `install` script. | `doctor.sh` points at `tools/ensure_godot.sh`. Review for ad-hoc downloads. |
| Tool-result floods from broad greps, repeated reads, and stacked verify/drive loops | Use the fixed brief/receipt schema (`tools/agent_budget.py`). Feature map path in the brief, discovery capped at 10, one verify and one drive before Ready. | `agent_budget.py` and `pr_hygiene.py` (Verify/Drive lines). Mid-task search thrash: review. |
| Committing `.import` files that Godot re-saved during a run (hundreds of unrelated files in a diff) | Commit `.import` changes only when the PR is about imports. Run `python3 tools/staged_import_hook.py install` in this checkout; the pre-commit hook rejects a staged `*.import` unless its source asset is staged too (`FLAGORIA_ALLOW_IMPORT_ONLY=1` or `git config flagoria.allowImportOnly true` opts out for an import-only PR). Revert unrelated imports with `git checkout -- ':(glob)**/*.import'`. A project-wide re-import is its own PR. | Local `staged_import_hook` pre-commit after install. Committed `.import` files match the current Godot defaults (#154), so a clean run makes no churn. Otherwise review. |
| Two Godot runs sharing one `user://` (settings, saves) and breaking each other | Give every run its own user dirs: separate `XDG_CONFIG_HOME`, `XDG_DATA_HOME` and `XDG_CACHE_HOME`. Work in your own `git worktree` off fresh `origin/main`, not in a checkout another task is using. | `tools/verify.sh` makes per-run temporary dirs (#155). Direct `godot` calls: review. |
| Killing another task's Godot (for example `pkill godot`) | Stop only processes this run started, by their recorded PIDs. | Review. |
| `git`/`gh` acting with a stale or wrong token because `GH_TOKEN` or `GITHUB_TOKEN` is set in the environment (push rejected, or a PR opened by the wrong account) | Run `git` and `gh` as `env -u GH_TOKEN -u GITHUB_TOKEN git …` / `… gh …` so the configured login is used. | Review. |
| Cursor commit authored or committed as an agent or noreply address | Use the trusted private repo-local identity config for the raw author and the raw committer. If it is missing, report a blocker and do not substitute an agent or noreply address. Leave a platform `Co-authored-by`, `Made-with`, or `Generated-by` trailer in place. Run `python3 tools/commit_identity_hook.py install` in this checkout. A GitHub merge committer is out of scope. | Local pre-push check after that install. Not CI. |
| A stacked PR still showing its parent's commits, or still targeting the parent branch, after the parent merged | After the parent merges: `gh pr edit <child> --base main`, then on the child branch `git fetch origin && git merge origin/main`, resolve, and push. Merged branches are not deleted automatically here, so GitHub does not retarget the child for you. Say in the child's description which PR it stacks on. | Review. |
| Rebasing a branch with an open PR and force-pushing it (review threads lose context, other worktrees break) | Bring the branch up to date by merging `origin/main` into it and pushing normally. Force-push only with the maintainer's approval (see below). | Review. |
| A PR that leaks an email address, a local path or an attribution, or that runs far over the size cap without saying why | Follow the privacy rule and the size rule above, and fill in `.github/pull_request_template.md` (including the `Size:` line). Run `python3 tools/pr_hygiene.py --base origin/main --title "…" --body-file body.md` before opening the PR. False positive: add an entry to `.github/pr-hygiene-allow.txt` (format in the header of `tools/pr_hygiene.py`). | The `pr-hygiene` workflow fails on email addresses, local paths, and over-cap PRs with no `## Why this is large` section or `Size justification:` line. Attribution phrases, the PR author's login and a missing `Size:` line are warnings only. Names: review. |
| A flaky netcode stress run fails the job only after the whole matrix (about 30 minutes) | Stress scenarios are deterministic: fixed seed, no sleep-based timing, wait on explicit state with a bounded timeout. The job stops at the first failed run. Each run has a 60 s budget. See [Writing netcode stress scenarios](#writing-netcode-stress-scenarios). | `tools/stress_scenario_lint.py` in `tools/verify.sh`. The job is `tools/stress_netcode.py`. |

## Human in the loop

Agents do not take irreversible project actions on their own. The maintainer approves merges and other high-impact steps.

- Never merge, deploy, change secrets or permissions, or run destructive git commands (force-push to shared branches, history rewrites, branch deletion, hard resets of others' work) without the maintainer's approval.
- Opening pull requests, filing issues, and commenting are fine.
- Merges happen only through the maintainer's pipeline and require approval or an existing standing permission that covers the specific merge. These four checks must pass on the current pull request head: `Load project and parse scripts`, `Privacy and size check`, `Netcode stress`, and `Gameplay drives`. Review threads must be resolved. For gameplay changes, the contributor runs the relevant feature drive, reviews its screenshots against the feature's expected behavior, and attaches or links the evidence before marking the pull request Ready.
- The optional gameplay and usability advisor provides advice only. Its approval is not a QA or merge gate. Contributors remain responsible for verification and evidence. Passing checks or receiving advice grants no merge, release, deployment, or other approval authority.

Related: the privacy rule above, and the small-PR and verify notes under Other house rules.
