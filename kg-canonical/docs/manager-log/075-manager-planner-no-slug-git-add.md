# Manager Log 075 - Manager Planner No-Slug Git Add

Date: 2026-06-04
Recorded at: 2026-06-04T21:28:45Z
Role: Manager / Guardian

## Status

The stopped-state manager planner avoided printing an exact manager-log path
without a slug, but its no-slug follow-up still printed a placeholder staging
command:

`git add <planner-next-manager-log-path> <changed-support-paths>`

That mixed "exact paths" wording with placeholder paths, which could mislead a
future manager-support thread into staging with non-exact guidance.

## Manager Action

Updated the no-slug manager planner follow-up to tell agents to rerun with a
lowercase slug before staging. The concrete-slug output remains the only mode
that prints the exact manager-log `git add` path.

Updated the workflow audit and workflow-script tests to require the safer
no-slug wording and reject copied `git add <planner-next-manager-log-path>`
placeholder targets.

## Validation Evidence

- `bash scripts/plan_next_manager_log.sh` - passed; no-slug output now says to
  rerun with a lowercase slug before staging.
- `uv run pytest tests/test_workflow_scripts.py` - passed, 43 tests.
- `bash scripts/audit_autonomous_workflow.sh` - clean, including
  `manager log planner avoids placeholder git add target`.
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
