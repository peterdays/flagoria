# Commit identity

Future commits must carry one configured personal-provider address as both the raw author email and the raw committer email, and their messages must not carry personal or agent-credit trailers. Existing history is not rechecked. This change adds the checker, the policy, and a proposed private startup. It does not install the workflow, set the address, or change branch protection, rulesets, secrets, or the saved environment.

## Checker

`tools/commit_identity.py` reads `FLAGORIA_COMMIT_IDENTITY_EMAIL` and compares it to the author email and the committer email stored on each commit that is reachable from the exact head and not reachable from the trusted base. Both fields must match that one address. Names are not compared. The same pass rejects credit trailers in the commit message, including `Co-authored-by`.

The head and the base must be full commit ids. If the base is not an ancestor of the head, the checker stops and does not walk unrelated history. An empty range fails closed. Output names the failing commit and the reason. It does not print either address.

Squash messages are a separate command. It builds the message implied by the repository's squash title mode and message mode and rejects credit trailers in that message. With `COMMIT_MESSAGES`, trailers in the branch commits are part of the default squash message, so deleting them only from the pull request text does not clear the squash check. `BLANK` would drop them; the mode is taken from the caller, not assumed.

`merge-via github-web` for merge, squash, or rebase is a separate failure. A GitHub web merge writes the web committer onto the resulting commit. That is not the configured address. `merge-via local` does not add that failure; the resulting object still has to pass `check`.

`stale` fails when the head id that was read is not the head id about to be recorded.

`controls` and the tree scan report executable hooks that append a credit trailer, other executable hooks, an unreadable hooks path, a commit template that contains a trailer, and hook runtimes added in the new commits (`.githooks/`, `.husky/`, `hooks.json`, and hook filenames). Sample hooks are ignored. A clean scan is not acceptance. The scan does not assume one hook name is the only insertion source.

Object reads pass `core.hooksPath` empty so a fetched repository cannot run its hooks. Config reads do not, because that override would hide the stored hooks path.

## What was verified

On current `main`, `e52d6765013e892351eb8f43358df3819e692535` is one new commit. Its raw author email and raw committer email are the same personal-provider address, and that address is the only personal-provider address used as both fields in existing history (19 commits). The other 238 commits pair a users-noreply author with the GitHub web committer. The new commit's message has one `Co-authored-by` trailer whose address is users-noreply. The object fetched here and `refs/pull/428/head` are that same id. The commit has a signature block; the API reports it unverified with an unknown key, so the signature is not an identity result.

`.git/hooks` in this checkout contains only `*.sample` files. Git does not run those names. `core.hooksPath` points at another directory. Two executable files there, `prepare-commit-msg.cursor.co-author` and `commit-msg.cursor.co-author`, contain a credit-trailer append, and the address embedded in them matches that trailer. A throwaway commit on this machine, with those hooks and a message that did not contain a trailer, stored a trailer. `--no-verify` did not stop it. Setting both raw addresses on that throwaway commit changed the author and committer and left the trailer in place. The same command with hooks pointed at an empty path stored no trailer. That object was still signed, so signing by itself did not insert the trailer. No post-commit hook is installed in that directory. This is a sufficient mechanism on this machine. It does not prove that the other run used these files, and it does not rule out a different runtime elsewhere.

The account email list is not readable with the integration token (403). The saved environment configuration is not readable from this run. No private identity variable is set. The checker therefore fails closed until that variable is set. The address was not copied into this tree.

## Controls that do not do this job

GitHub can restrict author email, committer email, and commit message text with rulesets, but only for an organization on an Enterprise plan. Those rules apply to new commits and, for a squash, to the resulting commit rather than to each branch commit. This repository is owned by a user account, has no rulesets, and cannot use those metadata rules. A committer rule that allowed GitHub web merges would also have to allow the web committer address, which this policy does not.

Required status checks are available on this plan. They run before GitHub creates the squash or merge commit, so they do not see that commit's committer. A `pull_request` workflow runs code from the pull request. For a same-repository pull request that code can read secrets. `pull_request_target` runs the workflow from the base and, by default, attaches its check to the base commit, which does not gate the head. The proposal checks out the base id, fetches `pull/<n>/head` from this repository, runs the base copy of the checker, clears the token in that step, and posts `commit-identity` on the head id only when that id is still current.

Hosted cloud agents are documented to author and commit as the platform agent and to add a co-author trailer when the starting person can be looked up, with no disable control. This checkout's default git identity is that platform agent. A command can still write other raw addresses into a new object, as the verified commit shows, but that is not a supported setting that keeps the platform from appending a trailer. Disabling hooks for one command is not that setting.

Repository squash settings are `COMMIT_OR_PR_TITLE` and `COMMIT_MESSAGES`. Branch protection was not readable (403). Nothing here changes those settings.

`tools/commit_identity_startup.sh` writes the private address into a git config file given by `FLAGORIA_COMMIT_IDENTITY_GITCONFIG` and then runs `controls`. It is not referenced by the saved environment. `start` is not awaited, so a startup script cannot be the gate. The saved environment was not modified.

## Activation that was not done

1. Put the existing personal-provider address, not a noreply address, in the secret `FLAGORIA_COMMIT_IDENTITY_EMAIL`. The value is the address only, with no display name and no extra whitespace. Do not store it in the repository.
2. Optionally point a private startup at `tools/commit_identity_startup.sh` with `FLAGORIA_COMMIT_IDENTITY_GITCONFIG` set. That sets git's default address for both fields. It does not remove trailers.
3. Install `tools/commit_identity_workflow.yml` under `.github/workflows/` without changing `pull_request_target` to `pull_request`. The web-merge job fails on purpose. Do not edit it so a web committer passes.
4. Require the `commit-identity` status, strict and pinned to the GitHub Actions app. A status from any other writer must not count. Anyone who can push can otherwise post a success status.
5. Final commits that should pass have to be created by a controlled git client that sets both raw fields, then checked as objects. A GitHub web merge, squash, or rebase does not preserve the committer. This plan cannot block that ref update with a metadata rule.

Until those steps are reviewed, a green pull request check is not this control.
