# 02 Role Contracts

## Executor Contract

- Read `AGENTS.md`, `GOAL.md`, `docs/kg-module-prd.md`, and the active brief.
- Implement one smallest useful slice.
- Preserve unrelated files and user changes.
- Run appropriate validation.
- Write `docs/session-logs/NNN-executor-*.md`.
- Commit scoped implementation and evidence files.

## Reviewer Contract

- Read the latest executor log, git diff/status, latest commit, PRD, and active
  brief.
- Verify that evidence supports the claim.
- Choose exactly one decision.
- Write `docs/reviewer-messages/NNN-*.md`.
- If `CONTINUE`, write or update the next brief and `GOAL.md`.
- Do not write product implementation code.

## Manager Contract

- Audit pair health and evidence quality.
- Intervene for drift, stale plans, repeated blockers, or weak validation.
- When `GOAL.md` contains `<stop-orchestrator/>`, keep work to manager process
  support unless fresh human direction changes the active role.
- Before writing a manager log, review the previous entry from
  `docs/manager-log latest:` or the `latest manager log:` line printed by
  `bash scripts/plan_next_manager_log.sh`.
- Record durable interventions under `docs/manager-log/`.
- Do not take over implementation unless the user explicitly redirects the
  manager to do so.
