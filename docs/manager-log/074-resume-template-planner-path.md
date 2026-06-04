# Manager Log 074 - Resume Template Planner Path

Date: 2026-06-04
Recorded at: 2026-06-04T21:23:39Z
Role: Manager / Guardian

## Status

The resume planner and static docs now route future threads through the live
planner for exact resume brief paths, but the human-approved resume template
still used `docs/briefs/007-<slice-name>.md` in its checklist.

That hardcoded example could become stale as soon as the next numbered brief is
no longer `007`, and a copied template could carry the stale validation command
into a candidate resume brief.

## Manager Action

Updated the resume template checklist to run the resume planner, rerun it with
the human-approved lowercase slug, copy into the exact `next brief:` path, and
replace `<planner-next-brief-path>` with the planner-printed exact path.

Updated the resume brief validator and workflow-script tests so real candidate
briefs reject copied `<planner-next-brief-path>` placeholders.

Added workflow audit coverage for the resume template itself, so future manager
support turns catch stale hardcoded `docs/briefs/007-<slice-name>.md` guidance.

## Validation Evidence

- `uv run pytest tests/test_workflow_scripts.py` - passed, 43 tests.
- `uv run pytest` - passed, 79 tests.
- `uv run python -m kg.validation` - passed with
  `"validation_status": "pass"`.
- `bash scripts/audit_autonomous_workflow.sh` - clean, including resume
  template planner-path checks.
- `bash scripts/agent_thread_status.sh` - clean; stop sentinel present and
  manager/process support mode preserved.
- `git diff --check` - passed.

## Guardrail

This is manager process support only. It does not create a resume brief, alter
`GOAL.md`, remove the stop sentinel, start product execution, or change runtime
graph behavior.
