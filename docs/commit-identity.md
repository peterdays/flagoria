# Commit identity

Future commits must carry one configured personal-provider address as both the raw author email and the raw committer email, and their messages must not carry personal or agent-credit trailers. Existing history is not rechecked. This change adds the checker and the policy. The startup script and the workflow file are proposals. They are not installed, and they are not usable enforcement. Nothing here sets the address or changes branch protection, rulesets, secrets, or the saved environment.

## Checker

`tools/commit_identity.py` reads `FLAGORIA_COMMIT_IDENTITY_EMAIL` and compares it to the author email and the committer email stored on each commit that is reachable from the exact head and not reachable from the trusted base. Both fields must match that one address. Names are not compared. The same pass rejects credit trailers in the commit message, including `Co-authored-by`.

The head and the base must be full commit ids. If the base is not an ancestor of the head, the checker stops and does not walk unrelated history. An empty range fails closed. Output names the failing commit and the reason. It does not print either address.

Squash messages are a separate command. It builds the message implied by the repository's squash title mode and message mode and rejects credit trailers in that message. With `COMMIT_MESSAGES`, trailers in the branch commits are part of the default squash message, so deleting them only from the pull request text does not clear the squash check. `BLANK` would drop them; the mode is taken from the caller, not assumed.

`merge-via github-web` for merge, squash, or rebase is a separate failure. A GitHub web merge writes the web committer onto the resulting commit. That is not the configured address. `merge-via local` does not add that failure; the resulting object still has to pass `check`.

`stale` fails when the head id that was read is not the head id about to be recorded. `plan` compares the head, base, title, body, and squash modes from the start of a run with the same fields at the end. Any change, or a failed check, is not an in-run match. The recorded state is still failure: a previous success remains until something posts again, and this proposal does not post success.

`controls` and the tree scan report executable hooks that append a credit trailer, other executable hooks, an unreadable hooks path, a commit template that contains a trailer, and hook runtimes added in the new commits (`.githooks/`, `.husky/`, `hooks.json`, and hook filenames). Sample hooks are ignored. A clean scan is not acceptance. The scan does not assume one hook name is the only insertion source.

Object reads pass `core.hooksPath` empty so a fetched repository cannot run its hooks. Config reads do not, because that override would hide the stored hooks path.

## What was verified

On current `main`, `e52d6765013e892351eb8f43358df3819e692535` is one new commit. Its raw author email and raw committer email are the same personal-provider address, and that address is the only personal-provider address used as both fields in existing history (19 commits). The other 238 commits pair a users-noreply author with the GitHub web committer. The new commit's message has one `Co-authored-by` trailer whose address is users-noreply. The object fetched here and `refs/pull/428/head` are that same id. The commit has a signature block; the API reports it unverified with an unknown key, so the signature is not an identity result.

`.git/hooks` in this checkout contains only `*.sample` files. Git does not run those names. `core.hooksPath` points at another directory. Two executable files there, `prepare-commit-msg.cursor.co-author` and `commit-msg.cursor.co-author`, contain a credit-trailer append, and the address embedded in them matches that trailer. A throwaway commit on this machine, with those hooks and a message that did not contain a trailer, stored a trailer. `--no-verify` did not stop it. Setting both raw addresses on that throwaway commit changed the author and committer and left the trailer in place. The same command with hooks pointed at an empty path stored no trailer. That object was still signed, so signing by itself did not insert the trailer. No post-commit hook is installed in that directory. This is a sufficient mechanism on this machine. It does not prove that the other run used these files, and it does not rule out a different runtime elsewhere.

The account email list is not readable with the integration token (403). The saved environment configuration is not readable from this run. No private identity variable is set. The checker therefore fails closed until that variable is set. The address was not copied into this tree.

## Controls that do not do this job

GitHub can restrict author email, committer email, and commit message text with rulesets, but only for an organization on an Enterprise plan. Those rules apply to new commits and, for a squash, to the resulting commit rather than to each branch commit. This repository is owned by a user account, has no rulesets, and cannot use those metadata rules. A committer rule that allowed GitHub web merges would also have to allow the web committer address, which this policy does not.

Required status checks are available on this plan. They run before GitHub creates the squash or merge commit, so they do not see that commit's committer. A `pull_request` workflow runs code from the pull request. For a same-repository pull request that workflow file can grant `statuses: write` and post any context, including one this proposal uses. The check is attributed to GitHub Actions, the same app a ruleset would pin, so pinning that app does not select one workflow file. No separate app is added here. That is a blocker: this proposal is not a spoof-resistant gate and must not be required.

`pull_request_target` would run the workflow file from the base. The proposal checks out that base id, fetches `pull/<n>/head` from this repository, and runs the base copy of the checker. The checker step has the private address and an empty token. Steps that call `gh` set `GH_TOKEN` and `GITHUB_TOKEN` to the workflow token and do not receive the private address. The file is not installed.

A run can clear a previous status only by posting again. The proposal posts failure at the start and failure at the end. It does not post success. An in-run match of head, base, title, body, and squash modes is not durable: changing squash settings does not emit a workflow event, so nothing would re-open a recorded success. A success that is not replaced also remains while a later run is still working.

Hosted cloud agents are documented to author and commit as the platform agent and to add a co-author trailer when the starting person can be looked up, with no disable control. This checkout's default git identity is that platform agent. A command can still write other raw addresses into a new object, as the verified commit shows, but that is not a supported setting that keeps the platform from appending a trailer. Disabling hooks for one command is not that setting.

Repository squash settings are `COMMIT_OR_PR_TITLE` and `COMMIT_MESSAGES`. Branch protection was not readable (403). Nothing here changes those settings.

`tools/commit_identity_startup.sh` can write the private address into the file named by `FLAGORIA_COMMIT_IDENTITY_GITCONFIG`. It does not set an include, and nothing waits for it before a commit. It exits non-zero after a successful write so that write is not reported as a gate. `start` is not awaited. The saved environment was not modified. This is not durable prevention.

## Blockers that remain

These are not implemented enforcement. The identity requirement is unchanged: both raw fields must be the configured personal-provider address, and a web committer is not that address.

1. The private address is not in `FLAGORIA_COMMIT_IDENTITY_EMAIL`. The account email list is not readable here, and the saved environment is not readable here. The checker fails closed without the variable. The address is not copied into this tree.
2. The startup script only writes a file. It is not an installed include and not a waited gate.
3. A GitHub web merge, squash, or rebase sets the committer itself. `merge-via github-web` reports that. No authorized control on this user-owned repository both keeps the requested committer and uses that button. Enterprise metadata rules are unavailable here, and a committer rule that allowed the web button would have to allow the web committer.
4. No authorized control pins a status to one workflow file. Requiring a GitHub Actions context does not stop another workflow with `statuses: write` from posting the same context. No app or permission was added.
5. Squash settings have no workflow event. A recorded success would not be rechecked when they change, and it would remain while a new run is in progress unless a new post replaces it. The proposal therefore posts failure only. It is not installed, and it is not a usable gate.
