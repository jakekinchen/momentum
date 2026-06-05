# Slice Brief 012 - EOD PRD Acceptance And Stop Readiness Audit

**Date:** 2026-06-04

## Human Direction

The user said: "make sure the coding pair is running still, we need this
completed and tested before EOD".

Reviewer decision `CONTINUE` in
`docs/reviewer-messages/012-review-jordan-plyometric-knee-safety.md` accepted
the Jordan plyometric knee safety slice and selected this final acceptance audit
as the next smallest useful step before any `STOP` decision.

## Objective

Create a durable, repo-evidence-based PRD acceptance and stop-readiness audit for
the EOD completion/testing milestone.

This slice should not make product-code changes. It should map the current
implementation and tests to the PRD P0 demo behaviors and test requirements,
rerun validation, and record whether the evidence supports a reviewer `STOP` or
whether exactly one concrete remaining gap needs another focused brief.

## Product / Project Value

The latest product slices closed the known EOD gaps for DB/KB equipment
resolution, Copilot fact cards, lower-back safety, and Jordan plyometric knee
safety. A final acceptance audit prevents the pair from adding speculative code
after the known P0 gaps are covered, while still giving the reviewer concrete
evidence for a stop or one last targeted plan.

## Acceptance Criteria

- Preserve deterministic graph behavior over LLM-driven eligibility.
- Do not use vector search for safety enforcement. Do not use embeddings,
  vector retrieval, or an LLM for safety enforcement.
- Do not claim ontology IDs, SNOMED codes, release IDs, access dates, or license
  status as verified unless `graph/ontology-lock.json` contains verified pinned
  values.
- Preserve `MAPS_TO` as ontology audit metadata only.
- Review `docs/kg-module-prd.md` P0 demo behaviors and test requirements against
  current repo evidence, especially:
  - resolver examples: `knee`, `left knee`, `bad lower back`, `kettlebell`,
    `no barbell`, `only dumbbells and kettlebell`, `exclude deadlifts`, `pecs`,
    `squats`, `press`, and unknown terms;
  - safety golden cases: knee closure, deep loaded knee flexion, plyometrics,
    equipment filtering, deadlift exclusion, limited-equipment alternatives,
    dislike versus explicit exclusion if currently represented, and ambiguous or
    unknown safety text;
  - workout-candidate evidence: selected receipts, filtered receipts,
    alternatives from the already-safe pool, target/equipment/safety graph paths;
  - Copilot evidence: adherence trend, sleep this week, churn risk, coach brief,
    source nodes, deterministic confidence, and absent-data behavior;
  - validation evidence: required seed files, graph schema checks, ontology lock
    truthfulness, and no verified ontology claims.
- Record exact file, test, command, or prior reviewer-log anchors for each
  accepted behavior.
- If current evidence supports EOD completion/testing, recommend reviewer
  `STOP` in the session log.
- If a missing product behavior blocks a stop, record exactly one smallest
  PRD-bound gap and the evidence anchor. Do not implement product code in this
  audit slice.

## Expected Files

- `docs/session-logs/013-executor-eod-prd-acceptance-audit.md`
- No product code, graph seed, or test changes unless the user explicitly
  redirects the slice.

## Validation Commands

```bash
bash scripts/validate_resume_brief.sh docs/briefs/012-eod-prd-acceptance-audit.md
UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run pytest
UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run python -m kg.validation
bash scripts/audit_autonomous_workflow.sh
node scripts/audit_codex_pair_state.mjs
git diff --check
```

## Evidence To Record

- Changed files.
- Validation command output.
- PRD acceptance matrix with exact anchors to current tests, modules, graph
  seeds, validation output, direct command output, or prior reviewer decisions.
- Confirmation that deterministic graph behavior is preserved.
- Confirmation that no vector safety enforcement, LLM eligibility, or unverified
  ontology claim was introduced.
- Explicit recommendation: reviewer `STOP` if sufficient, or one smallest
  remaining PRD-bound gap if not.

## Reachability / Demo Proof

Record command-backed proof for the final readiness claim. At minimum, include
one direct command or test anchor for each surface:

- resolver constraints for the PRD golden terms;
- `evaluate_candidates(...)` and `build_workout_candidates(...)` receipts for
  knee, plyometric, equipment, deadlift, alternatives, and selected-safe cases;
- member-context fact-card retrieval for adherence trend, sleep this week, churn
  risk, coach brief, and absent data;
- `python -m kg.validation` output showing validation pass and
  `verified=false`.

## Out Of Scope

- Product-code, graph-seed, or test changes during this audit slice.
- Creating external accounts, paid resources, or live ontology downloads.
- Verified ontology metadata, SNOMED/OPE/COPPER ID pinning, release IDs, access
  dates, or license claims.
- Vector retrieval, GraphRAG, embeddings, or LLM-generated safety decisions.
- New frontend, HTTP server, dashboard, or live API routing.
- Broad production hardening beyond the EOD completion/testing evidence audit.

## Stop Conditions

- The audit finds current evidence is sufficient for EOD completion/testing and
  recommends reviewer `STOP`.
- The audit finds one concrete missing PRD-bound product gap and records the
  evidence anchor for reviewer planning.
- The audit would require a human product, clinical, ontology, stack, or timing
  decision.
- The audit would require claiming unverified ontology metadata.

## Resume Checklist

- Human direction is recorded in this brief.
- Run `bash scripts/validate_resume_brief.sh docs/briefs/012-eod-prd-acceptance-audit.md`.
- Confirm `GOAL.md` points at
  `docs/briefs/012-eod-prd-acceptance-audit.md`.
- Confirm `<stop-orchestrator/>` is absent from `GOAL.md`.
- Run `bash scripts/agent_thread_status.sh`.
- Commit this brief and `GOAL.md` update with exact `git add` paths before
  starting an executor turn.
