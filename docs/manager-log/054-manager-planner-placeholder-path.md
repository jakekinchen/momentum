# Manager Log 054 - Manager Planner Placeholder Path

Date: 2026-06-04
Recorded at: 2026-06-04T20:19:25Z
Role: Manager / Guardian

## Status

`scripts/plan_next_manager_log.sh` avoided exact copy and `git add` commands in
no-slug mode, but still printed a command-shaped placeholder path as
`next manager log: docs/manager-log/NNN-<support-slug>.md`.

Because `scripts/agent_thread_status.sh` now includes the manager-log planner
dry run, future agent threads could see that placeholder path in the primary
orientation output and treat it as an exact target.

## Manager Action

Updated `scripts/plan_next_manager_log.sh` so no-slug mode prints
`next manager log: rerun with a lowercase slug to print exact path` and moves
the placeholder shape to `next manager log template: ...`.

Updated workflow-script tests and workflow audit coverage so no-slug planner
output keeps placeholder paths labeled as templates, while concrete slug mode
continues to print exact next manager-log paths.

## Validation Evidence

- `uv run pytest tests/test_workflow_scripts.py` - 37 passed
- `uv run pytest` - 73 passed
- `uv run python -m kg.validation` - `validation_status`: `pass`,
  `verified`: `false`
- `bash scripts/audit_autonomous_workflow.sh` - workflow audit clean
- `bash scripts/agent_thread_status.sh` - agent thread status clean and showed
  no-slug manager-log output without a placeholder exact next path
- `git diff --check` - clean

## Guardrail

This is manager process support only. It does not create a resume brief, alter
`GOAL.md`, remove the stop sentinel, start product execution, or change runtime
graph behavior.
