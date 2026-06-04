# Manager Log 058 - Agents Resume Planner

Date: 2026-06-04
Recorded at: 2026-06-04T20:35:18Z
Role: Manager / Guardian

## Status

`AGENTS.md` told future threads to validate a fresh resume brief before
updating `GOAL.md`, but it did not point them to
`bash scripts/plan_next_resume_brief.sh`.

Because `AGENTS.md` is the local entrypoint guidance, a future thread could
manually infer the next numbered brief path even though the repo already has a
planner for that exact step.

## Manager Action

Updated `AGENTS.md` so fresh human resume direction starts with the resume-brief
planner dry run, then reruns the planner with the human-approved lowercase
slice slug to get the exact candidate brief path and copy command.

Added workflow audit and workflow-script coverage so `AGENTS.md` keeps both the
resume planner pointer and the neutral
`bash scripts/validate_resume_brief.sh <planner-next-brief-path>` target.

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
