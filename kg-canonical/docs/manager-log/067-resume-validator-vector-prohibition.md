# Manager Log 067 - Resume Validator Vector Prohibition

Date: 2026-06-04
Recorded at: 2026-06-04T21:02:37Z
Role: Manager / Guardian

## Status

The resume-brief validator rejected unsafe affirmative vector safety claims by
raw substring. That made it possible for a safe prohibition such as `Do not use
vector search for safety enforcement` to be treated like the unsafe claim `Use
vector search for safety enforcement`.

Future resume threads should be able to quote the project guardrail directly
without tripping the validator, while affirmative vector safety enforcement must
still fail.

## Manager Action

Added a line-aware vector-safety rejection helper that allows explicit
prohibitions such as `do not`, `must not`, `never`, or `should not` before the
unsafe phrase.

Added resume-validator coverage proving the explicit prohibition passes while
the existing unsafe affirmative vector-search claim still fails.

## Validation Evidence

- `uv run pytest tests/test_workflow_scripts.py` - 41 passed.
- `uv run pytest` - 77 passed.
- `uv run python -m kg.validation` - `validation_status: pass`;
  `verified: false`.
- `bash scripts/audit_autonomous_workflow.sh` - workflow audit clean.
- `bash scripts/agent_thread_status.sh` - agent thread status clean; latest
  workflow artifact is
  `docs/manager-log/067-resume-validator-vector-prohibition.md`.
- `git diff --check` - clean.

## Guardrail

This is manager process support only. It does not create a resume brief, alter
`GOAL.md`, remove the stop sentinel, start product execution, or change runtime
graph behavior.
