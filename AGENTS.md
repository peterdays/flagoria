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
- Nothing is merged, released, or tagged without the owner's approval.
- Run `tools/verify.sh` before opening a pull request; CI runs the same check.
