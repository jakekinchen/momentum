# 06 Manager / Guardian Protocol

The Manager is the third-party overseer for the pair.

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

