# 06 Manager / Guardian Protocol

The Manager is the third-party overseer for the pair.

## Stopped-State Manager Support

When `GOAL.md` contains `<stop-orchestrator/>`, the Manager may make
process-support changes that help future Executor or Reviewer threads orient,
validate, or resume safely.

Stopped-state support must not start product execution, create a resume brief,
change runtime graph behavior, or alter `GOAL.md`.

Every stopped-state Manager support turn should leave a durable
`docs/manager-log/NNN-*.md` entry with the status, manager action, validation
evidence, and guardrail statement. Manager-only support does not need executor
session logs or reviewer decisions unless the thread is also acting in one of
those roles.

Use `docs/manager-log/000-template-manager-support.md` as the starting shape
for stopped-state manager support logs.

Before writing a new support log, review the previous manager-support entry
from the `docs/manager-log latest:` status/audit line or the `latest manager
log:` line printed by `bash scripts/plan_next_manager_log.sh`.

Use `bash scripts/plan_next_manager_log.sh <support-slug>` to preview the next
numbered manager-log path and exact copy command before writing a new support
log.

## Manager Checks

- Is the active brief still aligned with `docs/kg-module-prd.md`?
- Did the Executor make a small, reviewable change?
- Did the Executor validate the right behavior?
- Did the Reviewer choose exactly one valid decision?
- Is the next brief clear enough for an unattended executor turn?
- Are claims grounded in files, tests, logs, or commits?
- Is any safety, ontology, or product-policy assumption being treated as fact
  without evidence?

## Manager Interventions

Write `docs/manager-log/NNN-*.md` when:

- the pair drifts from the PRD;
- a repeated blocker appears;
- reviewer decisions are stale or unsupported;
- the active brief is too broad;
- the implementation is optimizing a nearby but wrong goal;
- a human decision is genuinely required.

Normal manager feedback should be short and specific:

```text
Status:
Concern:
Suggested steering:
Evidence to request next:
```
