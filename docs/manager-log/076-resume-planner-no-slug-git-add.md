# Manager Log 076 - Resume Planner No-Slug Git Add

Date: 2026-06-04
Recorded at: 2026-06-04T21:32:15Z
Role: Manager / Guardian

## Status

The resume-brief planner already avoided printing a fake candidate brief path
without a slug, but its no-slug follow-up still printed a placeholder staging
command:

`git add <planner-next-brief-path> GOAL.md`

That made the no-slug resume path less strict than the manager-log planner and
could mislead future threads into copying a placeholder as an "exact paths"
command.

## Manager Action

Updated the no-slug resume planner follow-up to tell agents to rerun with a
lowercase slug before staging. The concrete-slug output remains the only mode
that prints the exact resume-brief `git add` path.

Updated the workflow audit and workflow-script tests to require the safer
no-slug wording and reject copied `git add <planner-next-brief-path>`
placeholder targets.

## Validation Evidence

- `bash scripts/plan_next_resume_brief.sh` - passed; no-slug output now says to
  rerun with a lowercase slug before staging.
- `uv run pytest tests/test_workflow_scripts.py` - passed, 43 tests.
- `bash scripts/audit_autonomous_workflow.sh` - clean, including
  `resume planner avoids placeholder git add target`.
- `uv run pytest` - passed, 79 tests.
- `uv run python -m kg.validation` - passed with
  `"validation_status": "pass"`.
- `bash scripts/agent_thread_status.sh` - clean; stop sentinel present and
  manager/process support mode preserved.
- `git diff --check` - passed.

## Guardrail

This is process support only. It does not create a resume brief, alter
`GOAL.md`, remove the stop sentinel, start product execution, or change runtime
graph behavior.
