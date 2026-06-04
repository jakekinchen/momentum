# Manager Log 035 - README Manager Log Guidance

Date: 2026-06-04
Recorded at: 2026-06-04T19:28:45Z
Role: Manager / Guardian

## Status

`AGENTS.md` and the handoff documented that stopped-state manager-only support
turns should use `scripts/plan_next_manager_log.sh` and leave
`docs/manager-log/NNN-*.md` support logs.

`README.md` listed the manager-log planner under safe checks, but did not state
the stopped-state manager support rule directly on the repo-level start page.

## Manager Action

Updated `README.md` so future threads see that, while `<stop-orchestrator/>` is
present, manager-only process support may use
`bash scripts/plan_next_manager_log.sh` for the next numbered
`docs/manager-log/NNN-*.md` path and must leave a manager log for support
slices.

Updated the workflow audit and workflow-script tests so README must keep both
the manager-log planner pointer and the manager support-log requirement.

## Validation Evidence

- `uv run pytest tests/test_workflow_scripts.py`
- `uv run pytest`
- `uv run python -m kg.validation`
- `bash scripts/audit_autonomous_workflow.sh`
- `bash scripts/agent_thread_status.sh`
- `git diff --check`

## Guardrail

This is process support only. It does not create a resume brief, alter
`GOAL.md`, remove the stop sentinel, start product execution, or change runtime
graph behavior.
