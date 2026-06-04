# Slice Brief 009 - Copilot Sleep, Churn, And Coach Brief Fact Cards

**Date:** 2026-06-04

## Human Direction

The user said: "make sure the coding pair is running still, we need this
completed and tested before EOD".

Reviewer decision `CONTINUE` in
`docs/reviewer-messages/009-review-db-kb-punctuation-normalization.md`
accepted the DB/KB nudge correction and selected this as the next smallest
PRD-bound EOD completion/testing slice.

## Objective

Complete the missing deterministic Coach Copilot P0 fact-card coverage for:

- sleep this week;
- churn risk;
- coach brief.

The slice should extend the local member-context graph and
`kg.member_retrieval` with typed, source-backed fact cards. These queries should
read explicit graph facts only; they must not infer safety, churn, or coaching
truth from prose, vectors, or an LLM.

## Product / Project Value

The current member-context surface already proves adherence trend, active
injuries, available equipment, and goals. The PRD P0 demo also requires Copilot
answers for sleep this week, churn risk, and coach brief. This slice closes that
visible Copilot completion gap while preserving the graph-first contract.

## Acceptance Criteria

- Preserve deterministic graph behavior over LLM-driven eligibility.
- Do not use vector search for safety enforcement.
- Do not add vector retrieval as the source of truth for these fact cards.
- Do not claim ontology IDs, SNOMED codes, release IDs, access dates, or
  license status as verified unless `graph/ontology-lock.json` contains
  verified pinned values.
- Preserve `MAPS_TO` as ontology audit metadata only.
- Add minimal local `BiomarkerObservation` or equivalent PRD-compatible sleep
  data for Jordan's current week, with `SourceSpan` provenance.
- Add minimal local `ChurnSignal` data with explicit risk level, reason, and
  `SourceSpan` provenance. Do not invent or model-score churn beyond graph
  properties.
- Add a minimal local `CoachBrief` node with source-backed text.
- Add deterministic `kg.member_retrieval` functions for sleep this week, churn
  risk, and coach brief.
- Every new fact card must use `confidence="deterministic"`, include
  source nodes, and return a `not in graph` style card when data is absent.
- Existing adherence, equipment, injury, and goal fact-card tests must continue
  to pass.
- Record remaining PRD-pending work after this slice.

## Expected Files

- `graph/member_kg.seed.json`
- `kg/member_retrieval.py`
- `tests/test_member_retrieval.py`
- `docs/session-logs/010-executor-copilot-sleep-churn-coach-brief-fact-cards.md`

## Validation Commands

```bash
bash scripts/validate_resume_brief.sh docs/briefs/009-copilot-sleep-churn-coach-brief-fact-cards.md
UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run pytest tests/test_member_retrieval.py
UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run pytest
UV_CACHE_DIR=/private/tmp/fitgraph-uv-cache uv run python -m kg.validation
bash scripts/audit_autonomous_workflow.sh
node scripts/audit_codex_pair_state.mjs
```

## Evidence To Record

- Changed files.
- Validation command output.
- Exact fact-card output for sleep this week, churn risk, and coach brief.
- Source nodes for every new fact-card claim.
- Confirmation that deterministic graph behavior is preserved.
- Confirmation that no vector safety enforcement, LLM eligibility, or
  unverified ontology claim was introduced.
- Remaining PRD-pending work, if any.

## Reachability / Demo Proof

At minimum, record direct command-backed examples for:

- `member_retrieval.sleep_this_week("Member:jordan")`;
- `member_retrieval.churn_risk("Member:jordan")`;
- `member_retrieval.coach_brief("Member:jordan")`;
- an absent-member or absent-data path returning a no-supporting-fact card.

## Out Of Scope

- Creating external accounts, paid resources, or live ontology downloads.
- Verified ontology metadata or SNOMED/OPE/COPPER ID pinning.
- Vector retrieval, GraphRAG, or LLM-generated fact-card source claims.
- Broad member-context expansion beyond the minimal sleep, churn, and coach
  brief P0 facts.
- New frontend, HTTP server, or live API routing.
- Replacing deterministic safety enforcement with LLM, embedding, or vector
  retrieval behavior.

## Stop Conditions

- The slice would require a product decision about churn scoring beyond
  explicit graph seed properties.
- The slice would require claiming unverified ontology metadata.
- The slice would replace deterministic graph facts with LLM, embedding, or
  vector retrieval behavior.
- A human explicitly redirects the EOD completion/testing scope.

## Resume Checklist

- Human direction is recorded in this brief.
- Run `bash scripts/validate_resume_brief.sh docs/briefs/009-copilot-sleep-churn-coach-brief-fact-cards.md`.
- Confirm `GOAL.md` points at
  `docs/briefs/009-copilot-sleep-churn-coach-brief-fact-cards.md`.
- Confirm `<stop-orchestrator/>` is absent from `GOAL.md`.
- Run `bash scripts/agent_thread_status.sh`.
- Commit this brief and `GOAL.md` update with exact `git add` paths before
  starting an executor turn.
