# Manager Log 049 - Operating Model Stopped State

Date: 2026-06-04
Recorded at: 2026-06-04T20:01:19Z
Role: Manager / Guardian

## Status

`docs/autonomous-workflow/01-operating-model.md` described the normal Executor,
Reviewer, and Manager roles, but it did not state the stopped-state mode that is
currently active in this repo.

Future threads reading only the operating model could miss that
`<stop-orchestrator/>` stops executor product slices while still allowing
manager process-support work with durable manager logs.

## Manager Action

Added a stopped-state section to the operating model. It says executor product
slices are stopped until fresh human direction changes the goal, manager support
may continue only as process support, future manager turns should review
`docs/manager-log latest:`, and support turns must leave
`docs/manager-log/NNN-*.md`.

Updated the workflow audit and workflow-script tests so the operating model
must keep that stopped-state guidance.

## Validation Evidence

- `uv run pytest tests/test_workflow_scripts.py`
- `uv run pytest`
- `uv run python -m kg.validation`
- `bash scripts/audit_autonomous_workflow.sh`
- `bash scripts/agent_thread_status.sh`
- `git diff --check`

## Guardrail

This is manager process support only. It does not create a resume brief, alter
`GOAL.md`, remove the stop sentinel, start product execution, or change runtime
graph behavior.
