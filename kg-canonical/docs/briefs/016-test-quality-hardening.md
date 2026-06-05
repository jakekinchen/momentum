# Test Quality Hardening

**Date:** 2026-06-05

## Human Direction

User instruction: "proceed with all of these, use subagents"

Context: the user approved implementing the test-quality recommendations from
the assessment of the candidate-assessment dashboard submission. The approved
recommendations are committed automated dashboard coverage, dashboard fixture
drift protection, stronger workout generator golden tests, assessment import
invariants over all imported records, and negative importer tests.

## Objective

Harden the FitGraph candidate-assessment test suite so it demonstrates the
dashboard and graph-backed product flows more comprehensively while preserving
the deterministic KG runtime contract.

## Product / Project Value

This slice turns the previous manual quality assessment into durable regression
coverage. It raises confidence that the candidate dashboard, imported fixture
graphs, workout generator, and Coach Copilot remain graph-backed, source-backed,
and deterministic without introducing LLM-driven eligibility or vector-search
safety enforcement.

## Acceptance Criteria

- Add committed automated dashboard coverage for render, receipt filtering,
  evidence details, Copilot prompt switching, chart presence, and mobile reach.
- Add a fixture drift test that compares the static dashboard fixture against
  graph-backed generator and Copilot outputs.
- Strengthen workout generator tests with exact selected, filtered,
  alternative, unresolved, missing-member, and prompt-branch expectations.
- Strengthen assessment import tests with all-record provenance, required
  stress-property, source-span, family-classification, and malformed-input
  checks.
- Preserve deterministic graph behavior over LLM-driven eligibility.
- Preserve `MAPS_TO` as ontology audit metadata.
- Do not claim ontology IDs, SNOMED codes, release IDs, access dates, or
  license status are verified unless `graph/ontology-lock.json` contains
  verified pinned values.

## Expected Files

- `tests/test_assessment_import.py`
- `tests/test_workout_generator.py`
- `tests/test_dashboard_contract.py`
- `tests/test_dashboard_browser.py`
- `tests/test_copilot.py`
- `pyproject.toml`
- `docs/session-logs/017-executor-test-quality-hardening.md`
- `docs/reviewer-messages/017-review-test-quality-hardening.md`
- `docs/autonomous-workflow/08-scaffold-adoption-matrix.md`
- `GOAL.md`

## Validation Commands

```bash
uv run pytest
uv run python -m kg.validation
bash scripts/audit_autonomous_workflow.sh
node scripts/audit_codex_pair_state.mjs
bash scripts/validate_resume_brief.sh docs/briefs/016-test-quality-hardening.md
```

## Evidence To Record

- Changed files.
- Validation command output.
- Automated browser or DOM proof for the dashboard.
- Exact generator, importer, Copilot, and dashboard-drift behaviors now pinned.
- Explicit confirmation that no unverified ontology claims were introduced.
- Remaining PRD-pending work, if any.

## Reachability / Demo Proof

`uv run pytest` must exercise the new dashboard, drift, importer, generator, and
Copilot coverage. The dashboard proof should run from the committed test suite
rather than relying only on a one-off manual browser smoke.

## Out Of Scope

- No production service, auth, deploy, payment, or external account work.
- No live ontology downloads.
- No SNOMED CT, OPE, or COPPER verification claims.
- No replacement of deterministic safety enforcement with LLM, embedding, or
  vector retrieval behavior.
- No broad product redesign beyond testability hooks that are necessary for
  durable coverage.

## Stop Conditions

- Human direction is missing or ambiguous.
- The slice would require claiming unverified ontology metadata.
- The slice would replace deterministic safety enforcement with LLM, embedding,
  or vector retrieval behavior.
- A product, clinical, ontology, or stack decision requires human approval.

## Resume Checklist

Before an executor starts:

- Remove or intentionally replace `<stop-orchestrator/>` in `GOAL.md`.
- Run `bash scripts/plan_next_resume_brief.sh`, then rerun it with the
  human-approved lowercase slice slug.
- Copy this template into the exact `next brief:` path printed by the planner.
- Run `bash scripts/validate_resume_brief.sh docs/briefs/016-test-quality-hardening.md`
  on the drafted brief before updating `GOAL.md`.
- Update `GOAL.md` to point at the new active brief.
- Run `bash scripts/agent_thread_status.sh`.
- Commit the brief and `GOAL.md` update with exact paths:
  `git add docs/briefs/016-test-quality-hardening.md GOAL.md`
