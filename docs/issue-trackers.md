# Keep trackers outside milestone task lists

## Default

Keep roadmap and epic tracker issues unmilestoned. Reuse each existing tracker as the single maintained source for its broader scope. Do not introduce a parallel roadmap document or another milestone for tracking.

Milestones contain executable tasks with defined acceptance criteria. A tracker explains how those tasks fit together; it is not another implementation task to count alongside them.

## Preserve history and links

Retain the original tracker issue URLs, discussion, and history. Link the remaining and completed child tasks from each tracker. Keep the scope description in the tracker and the implementation details in the child tasks, rather than maintaining duplicate descriptions.

Deferred work remains linked and explicitly marked as deferred. Deferral does not count as completed implementation.

## Apply the new issue shape

New trackers use the same native title, What it does, Scope, and Done when sections as other new issues.

For a tracker:

- What it does states the outcome the linked work supports.
- Scope names the included tasks and explicit exclusions.
- Done when requires acceptance of every included task, with any deferred scope recorded separately.

Close a tracker only when its stated acceptance conditions are met. Do not infer completion from the number of closed issues or a milestone percentage.

## Proposed transition

Make no migration now. If this policy is accepted, review existing milestone entries individually. Remove a tracker from a milestone only after confirming that its executable scope remains represented by linked tasks. Preserve its URL and history throughout.

This is a proposal, not an instruction to rewrite existing issues or change milestone assignments.
