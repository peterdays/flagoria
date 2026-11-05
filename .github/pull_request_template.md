<!--
Neutral project voice: no names, attributions, email addresses or local paths
(see AGENTS.md). The pr-hygiene check fails on email addresses and local paths,
and on an empty Feature file: line or an empty "## How it was checked" section.
Gameplay PRs also need a non-empty "## Evidence" section.
-->

## Why

<!-- The problem or goal, in a sentence or two. -->

## What

<!-- What changed. One concern per pull request. -->

## How it was checked

<!-- Required. For example: tools/verify.sh, tests, a two-player run, screenshots.
     Do not leave this section empty. -->

Feature file: <!-- Required. "added" or "updated" (name the file under
.cursor/skills/verify-flagoria/features/, plus its Drive: line when a player can
reach the feature), or "not player-facing". See docs/architecture.md. -->

## Evidence

<!-- Required on gameplay PRs (paths matching tools/play_review_paths.py).
     Include a github user-attachments image or video URL, or the text
     "CI drive artifact" when verify-drive uploaded screenshots. -->

## Links

<!-- Closes #N, or Part of #N. Say which PR this stacks on, if any. -->

Size: ~N code lines (excl. .import/assets/docs)

Time cost: <!-- Expected CI or verify time each new test, verify step or job
adds, for example "~10 s in verify" or "none". Costly checks are allowed when
they are worth it; say why. Each workflow run's "Job times" summary shows the
actual times against recent main runs and warns past 5 min per job. -->

<!--
Cap: about 1,000 changed lines of hand-written code. A larger PR needs a
"## Why this is large" section or a "Size justification:" line, or the
pr-hygiene check fails.
-->
