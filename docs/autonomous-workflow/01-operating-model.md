# 01 Operating Model

The autonomous workflow uses three roles.

## Executor

The Executor implements one smallest useful slice from the active brief. The
Executor validates the slice, records evidence, and commits scoped changes.

## Reviewer / Planner

The Reviewer audits the latest executor work from repo evidence. The Reviewer
chooses exactly one decision: `CONTINUE`, `NUDGE`, `REDIRECT`, `STOP`, or
`ESCALATE`.

## Manager / Guardian

The Manager is the third-party overseer. The Manager keeps the pair aligned to
the PRD, watches for stale plans or weak evidence, and intervenes only when the
workflow itself needs steering.

## Evidence Rule

Do not close work from intent, prose, or apparent effort. Close work from files,
tests, command output, logs, commits, and product-relevant demonstrations.

