# Manager Log 060 - Audit Suggested Checks

Date: 2026-06-04
Recorded at: 2026-06-04T20:41:37Z
Role: Manager / Guardian

## Status

`scripts/audit_autonomous_workflow.sh` ended its `Project commands` section with
`suggested checks: uv sync && uv run pytest`.

That was narrower than the current stop-state validation shape used by the
handoff, README, manager logs, and support-loop follow-up, which includes both
the test suite and `uv run python -m kg.validation`.

## Manager Action

Changed the audit footer to print a small suggested-checks list:

- `uv run pytest`
- `uv run python -m kg.validation`

When `uv` is unavailable, the fallback now prints the equivalent `python -m`
commands.

Added workflow-script coverage so the audit output keeps the KG validation
suggestion and does not return to the old pytest-only `uv sync` line.

## Validation Evidence

- `uv run pytest tests/test_workflow_scripts.py` - 38 passed.
- `uv run pytest` - 74 passed.
- `uv run python -m kg.validation` - `validation_status: pass`;
  `verified: false`.
- `bash scripts/audit_autonomous_workflow.sh` - workflow audit clean.
- `bash scripts/agent_thread_status.sh` - agent thread status clean.
- `git diff --check` - clean.

## Guardrail

This is manager process support only. It does not create a resume brief, alter
`GOAL.md`, remove the stop sentinel, start product execution, or change runtime
graph behavior.
