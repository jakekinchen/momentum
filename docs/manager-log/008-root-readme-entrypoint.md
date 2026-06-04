# Manager Log 008 - Root README Entrypoint

Date: 2026-06-04
Recorded at: 2026-06-04T18:13:36Z
Role: Manager / Guardian

## Status

Future agent threads now have `AGENTS.md`, `docs/agent-thread-handoff.md`, and
`scripts/agent_thread_status.sh`, but the repo root did not have a conventional
`README.md` entrypoint. A thread entering through the normal repo front door
could miss the stopped-loop handoff path.

## Manager Action

Added `README.md` with:

- the one-command agent status check;
- the current stopped M0-M5 state;
- safe validation commands;
- deterministic graph and ontology guardrails.

Updated:

- `scripts/audit_autonomous_workflow.sh`
- `docs/agent-thread-handoff.md`
- `docs/autonomous-workflow/07-document-and-artifact-map.md`
- `tests/test_workflow_scripts.py`

## Guardrail

This is a process/documentation change only. It does not remove the stop
sentinel, start an executor product slice, or change FitGraph runtime behavior.
