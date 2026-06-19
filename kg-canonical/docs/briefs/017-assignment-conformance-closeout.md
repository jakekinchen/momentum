# Assignment Conformance Closeout

**Date:** 2026-06-06

## Human Direction

User instruction: "/goal read /Users/kelly/Developer/camifit-app/docs/briefs/046-assignment-conformance-closeout.md and carry out the tasks and update the document as you go, use subagents to help and you review their work"

## Objective

Resume product work for the KG side of the app-level assignment closeout by
supporting reliable module-form Python gates, an assignment-mode graph artifact
for the Swift runtime, and deterministic app-facing workout generation support.

## Product / Project Value

This slice moves FitGraph from a Python/static-dashboard proof toward the
CamiFit app submission path while preserving the core invariant: deterministic
graph traversal decides workout eligibility, safety filtering, alternatives,
decision receipts, and fact-card grounding. The app may render or summarize the
results, but the LLM must not decide eligibility.

## Acceptance Criteria

- Use `uv run python -m pytest` for active KG test commands in the app
  monorepo gate and active README command surfaces.
- Preserve deterministic graph behavior over LLM-driven eligibility.
- Preserve `MAPS_TO` as ontology audit metadata unless verified source data is
  supplied in a later ontology slice.
- Do not claim ontology IDs, SNOMED codes, release IDs, access dates, or
  license status are verified unless `graph/ontology-lock.json` contains
  verified pinned values.
- Keep member safety and equipment constraints as hard blocks.
- Keep any resolver fallback confidence-aware and unable to relax hard medical
  or equipment blocks.

## Expected Files

- `GOAL.md`
- `README.md`
- `docs/briefs/017-assignment-conformance-closeout.md`
- `docs/session-logs/018-executor-assignment-conformance-closeout.md`
- App-root closeout files and Swift package files as listed in
  `../docs/briefs/046-assignment-conformance-closeout.md`.

## Validation Commands

```bash
uv run pytest
uv run python -m pytest
uv run python -m kg.validation
bash scripts/audit_autonomous_workflow.sh
node scripts/audit_codex_pair_state.mjs
bash scripts/validate_resume_brief.sh docs/briefs/017-assignment-conformance-closeout.md
```

`uv run pytest` is retained here only because the current KG workflow validator
requires that literal legacy command in active resume briefs. The app-root gate
and active README command surfaces use `uv run python -m pytest`, which is the
working invocation for this environment.

## Evidence To Record

- Changed files.
- Validation command output.
- Assignment graph reachability proof from Swift/KGKit.
- Explicit confirmation that no unverified ontology claims were introduced.
- Remaining assignment gaps after this closeout slice.

## Reachability / Demo Proof

The app-root Swift tests should prove that KGKit can load the assignment-mode
artifact, evaluate all 50 golden exercises, generate a graph-derived workout,
convert it into an app-native routine, and render decision evidence.

## Out Of Scope

- No live ontology downloads.
- No verified SNOMED CT, OPE, COPPER, release, access-date, or license claims.
- No replacement of deterministic safety enforcement with LLM, embedding, or
  vector retrieval behavior.
- No external accounts, paid resources, production auth, or persistent service
  deployment.

## Stop Conditions

- The slice would require claiming unverified ontology metadata.
- The slice would replace deterministic safety enforcement with LLM, embedding,
  or vector retrieval behavior.
- A product, clinical, ontology, or stack decision requires additional human
  approval.

## Resume Checklist

Before an executor starts:

- Remove or intentionally replace `<stop-orchestrator/>` in `GOAL.md`.
- Run `bash scripts/plan_next_resume_brief.sh`, then rerun it with the
  human-approved lowercase slice slug.
- Copy this template into the exact `next brief:` path printed by the planner.
- Run `bash scripts/validate_resume_brief.sh docs/briefs/017-assignment-conformance-closeout.md`
  on the drafted brief before updating `GOAL.md`.
- Update `GOAL.md` to point at the new active brief.
- Run `bash scripts/agent_thread_status.sh`.
- Commit the brief and `GOAL.md` update with exact paths:
  `git add docs/briefs/017-assignment-conformance-closeout.md GOAL.md`
