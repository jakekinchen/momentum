# Slice Brief - Full Assessment Delivery

**Date:** 2026-06-05

## Human Direction

Proceed.

The preceding human request asked: "what's left? can we get the rest of the
project finished out?" The approved continuation is to move beyond the completed
FitGraph KG-module closeout and finish the broader candidate-assessment
dashboard submission path.

## Objective

Deliver a runnable, staff-level candidate-assessment submission on top of the
completed deterministic FitGraph KG kernel: fixture conformance import,
expanded generated graph data, member-context coverage, CLI/API contracts,
dashboard surface, documentation, evidence, and real-world tests.

## Product / Project Value

This slice turns FitGraph from a strong KG module into the full coach-facing
assessment deliverable. The finished repo must prove that workout safety,
equipment filtering, exclusions, alternatives, and Copilot facts are driven by
typed graph data and source-backed receipts rather than LLM improvisation.

## Acceptance Criteria

- Preserve deterministic graph behavior over LLM-driven eligibility.
- Preserve `MAPS_TO` as ontology audit metadata.
- Do not use vector search for safety enforcement.
- Do not claim ontology IDs, SNOMED codes, release IDs, access dates, or license
  status are verified unless `graph/ontology-lock.json` contains verified
  pinned values.
- Import the external candidate-assessment exercise and member fixtures without
  mutating the external snapshot.
- Real-world conformance tests prove the expected fixture counts: 50 exercises,
  19 muscle groups, 9 loaded body regions, 36 movement patterns, and 32
  equipment terms.
- Member-context tests cover Jordan's equipment, active left-knee injury,
  preferences, adherence, sleep, churn, coach brief, workouts, labs, biomarkers,
  chat history, and deterministic no-supporting-fact behavior.
- Workout-generation tests cover a full prompt/time input, left-knee safety,
  DB/KB-only equipment, deadlift exclusion, filtered receipts, and alternatives
  drawn only from the selected safe pool.
- Copilot tests cover quick prompts and chart series for brief, adherence,
  sleep, churn risk, message pattern, and last-four-weeks comparison.
- A runnable dashboard is present with mock coach/member view, workout
  generator, provenance trace, alternatives, Copilot quick prompts, charts, and
  source/evidence affordances.
- README documents architecture, stack choices, local run commands, AI usage,
  trade-offs, evaluation plan, limitations, and 2-3 example prompts with
  generated plans and provenance traces.

## Expected Files

- `GOAL.md`
- `docs/briefs/015-full-assessment-delivery.md`
- `docs/session-logs/016-executor-full-assessment-delivery.md`
- `docs/reviewer-messages/016-review-full-assessment-delivery.md`
- `docs/autonomous-workflow/08-scaffold-adoption-matrix.md`
- `docs/candidate-assessment-fitgraph-synthesis-plan.md`
- `docs/external/candidate-assessment/**`
- `graph/**`
- `kg/**`
- `tests/**`
- dashboard or app files needed for a runnable local submission
- `README.md`

## Validation Commands

```bash
uv run pytest
uv run python -m kg.validation
bash scripts/audit_autonomous_workflow.sh
node scripts/audit_codex_pair_state.mjs
git diff --check
```

If the dashboard needs a dev server, run the dashboard test/build command and
perform a browser verification pass.

## Evidence To Record

- Changed files.
- Validation command output.
- Fixture import/conformance proof.
- Workout-generation demo proof with provenance and alternatives.
- Copilot demo proof with fact cards and chart series.
- Dashboard reachability proof.
- Explicit confirmation that deterministic graph behavior is preserved.
- Explicit confirmation that no vector search, LLM eligibility, or verified
  ontology claim was introduced.
- Remaining PRD-pending work, if any.

## Reachability / Demo Proof

At minimum, record commands that import the full assessment fixtures, generate a
Jordan workout from a real coach prompt, answer Copilot quick prompts, and open
or verify the dashboard surface.

## Out Of Scope

- External accounts, paid resources, or live ontology downloads.
- Verified ontology metadata or SNOMED/OPE/COPPER ID pinning.
- Real member data or PHI.
- Replacing deterministic graph safety with LLM, embedding, vector, or GraphRAG
  behavior.

## Stop Conditions

- The slice would require claiming unverified ontology metadata.
- The slice would replace deterministic safety enforcement.
- The dashboard cannot be made runnable without a product or stack decision that
  contradicts the human direction.
- A human explicitly redirects the full-assessment delivery scope.

## Resume Checklist

Before an executor starts:

- Remove or intentionally replace `<stop-orchestrator/>` in `GOAL.md`.
- Run `bash scripts/plan_next_resume_brief.sh`, then rerun it with the
  human-approved lowercase slice slug.
- Copy this template into the exact `next brief:` path printed by the planner.
- Run `bash scripts/validate_resume_brief.sh docs/briefs/015-full-assessment-delivery.md`
  on the drafted brief before updating `GOAL.md`.
- Update `GOAL.md` to point at the new active brief.
- Run `bash scripts/agent_thread_status.sh`.
- Commit the brief and `GOAL.md` update with exact `git add` paths.
