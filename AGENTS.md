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

## Human in the loop

Agents do not take irreversible project actions on their own. The maintainer approves merges and other high-impact steps.

- Never merge, deploy, change secrets or permissions, or run destructive git commands (force-push to shared branches, history rewrites, branch deletion, hard resets of others' work) without the maintainer's approval.
- Opening pull requests, filing issues, and commenting are fine.
- Merges happen only through the maintainer's pipeline: CI green, Play Sentinel PASS (the project's gameplay and usability review), and review threads resolved.

Related: the privacy rule above, and the small-PR and verify notes under Other house rules.
