# Manager Log 007 - AGENTS First-Hop Orientation

Date: 2026-06-04
Recorded at: 2026-06-04T18:11:33Z
Role: Manager / Guardian

## Status

Future FitGraph agent threads read `AGENTS.md` first, but the newer status
command and handoff document previously lived one step deeper in the workflow
docs. That made the stop/resume state discoverable, but not immediate.

## Manager Action

Added an `Agent Thread Orientation` section to `AGENTS.md` that tells future
threads to run:

```bash
bash scripts/agent_thread_status.sh
```

The section also points to `docs/agent-thread-handoff.md` and reinforces that
executor product slices must not start while `GOAL.md` contains
`<stop-orchestrator/>`.

Updated:

- `docs/agent-thread-handoff.md`
- `tests/test_workflow_scripts.py`

## Guardrail

This is a process/documentation change only. It does not remove the stop
sentinel, start an executor product slice, or change FitGraph runtime behavior.
