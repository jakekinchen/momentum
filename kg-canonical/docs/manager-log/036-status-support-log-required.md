# Manager Log 036 - Status Support Log Required

Date: 2026-06-04
Recorded at: 2026-06-04T19:30:41Z
Role: Manager / Guardian

## Status

`scripts/agent_thread_status.sh` is the first command future agent threads run.
While the stop sentinel was present, it printed the manager-log planner command
but did not directly state that manager-only support slices must leave a
`docs/manager-log/NNN-*.md` support log.

That requirement existed in `AGENTS.md`, `README.md`, and the manager protocol,
but the status command itself could still be read as planner-only guidance.

## Manager Action

Updated `scripts/agent_thread_status.sh` to print
`manager support log required: docs/manager-log/NNN-*.md` while the stop
sentinel is present.

Updated the workflow audit and workflow-script tests so the status command must
keep both the manager-log planner pointer and the support-log requirement.

Renamed the audit section from status resume guidance to status stopped-state
guidance because it now covers both manager-support and resume-planning output.

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
