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
- Small, self-contained pull requests, one concern each. Pull requests double as documentation: focused commits and a short why/what description should let a reader understand exactly what changed and why. Never bundle several issues or features into one pull request; stack dependent pull requests instead, and reference the related issue numbers.
- Nothing is merged, released, or tagged without the owner's approval.
- Run `tools/verify.sh` before opening a pull request; CI runs the same check.
- For scripted verification recipes (launch, doctor, drive, evidence), use `.cursor/skills/verify-flagoria/` when that skill is present.
