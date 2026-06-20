---
name: goal-loop
description: Run a persistent objective loop until completion or a real blocker. Use when Codex is asked to keep working toward a goal, perform overnight or repeated sweeps, optimize to a target metric, continue until tests pass, maintain a /goal-style loop, or periodically check whether the objective is finished.
---

# Goal Loop

Use this skill for objective-driven work where one prompt should not end at the first partial result. A goal loop must have an explicit objective, proof target, state ledger, cadence, and stop conditions.

## Repo Notes

- Treat `GOAL.md` and active docs under `docs/` as the durable loop contract after the latest direct user instruction.
- Prefer existing workflow scripts when appropriate: `scripts/start_codex_goal_loop.sh`, `scripts/stop_codex_goal_loop.sh`, `scripts/audit_autonomous_workflow.sh`, `scripts/run_codex_pair_cycle.sh`, and `scripts/run_monorepo_gates.sh`.
- Keep app, KG, website, motion-reference, and Coach/Future Coach runtime contexts distinct.
- Stop rather than paper over proof gaps involving live camera, installed app behavior, pose tracking, hardware, or health/safety constraints.

## Workflow

1. Define the goal.
   - State the outcome in observable terms.
   - Identify the proof target: test suite, benchmark, page-load threshold, docs coverage, deployment check, issue queue state, or live app behavior.
   - Identify what "done" means and what counts as blocked.

2. Create or update the ledger.
   - Prefer an existing repo ledger such as `goal.md`, `GOAL.md`, or `.factory/goal-loop.md`.
   - Use `references/goal-ledger-template.md` for new ledgers.
   - Record objective, acceptance criteria, current proof, iteration log, blockers, and next action.

3. Iterate.
   - Inspect current state.
   - Make the smallest useful change or gather the next missing proof.
   - Run the proof surface.
   - Update the ledger with result, evidence, and next step.
   - Continue until done or blocked.

4. Manage cadence.
   - Use tight loops for fast local checks.
   - Use slower cadence for external reviews, CI, deploy propagation, or long-running jobs.
   - Avoid burning time on repeated identical failures; after three materially identical blocked iterations, report the blocker and what would unblock it.

5. Close.
   - Verify the done condition against the proof target.
   - Report final proof, ledger path, remaining risks, and any running process left active.
   - Do not claim completion from code changes alone when the goal requires visible, benchmark, CI, or production proof.

## Good Goal Shapes

- "Keep improving the docs until every public command in `scripts/` is documented."
- "Loop until the home page local load is under 50 ms or explain the hard blocker."
- "Keep checking this PR and address new review comments until no actionable comments remain."
- "Continue the migration until tests pass and the old path is removed."

## Guardrails

- Keep user-facing truth surfaces ahead of internal confidence.
- Keep proof state honest: local, mock-backed, CI, production, hardware, or unverified.
- Do not run indefinite loops without a ledger and a stop condition.
- Do not continue expensive or risky loops after the objective becomes ambiguous.
