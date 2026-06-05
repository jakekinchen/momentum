# Manager Log 033 - Agents Manager Log Guidance

Date: 2026-06-04
Recorded at: 2026-06-04T19:25:04Z
Role: Manager / Guardian

## Status

The primary stopped-state status path pointed manager-support turns to
`scripts/plan_next_manager_log.sh`, but the root `AGENTS.md` orientation still
only named the status command, handoff, stop sentinel, and resume validation.

That left the first instruction file future threads read without an explicit
manager-log planner pointer or support-log requirement.

## Manager Action

Updated `AGENTS.md` to tell stopped-state manager-only support turns to use
`bash scripts/plan_next_manager_log.sh` for the next numbered
`docs/manager-log/NNN-*.md` path and to leave a manager log for any support
slice.

Updated the autonomous workflow audit and workflow-script tests so root agent
orientation must keep pointing to the manager-log planner and manager support
logs.

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
