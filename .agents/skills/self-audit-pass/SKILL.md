---
name: self-audit-pass
description: Audit and refine an agent's own work before human handoff. Use when Codex has produced code, docs, generated assets, PR changes, or automation outputs and needs an internal review pass for correctness, scope, tests, proof state, documentation, security, and visible behavior before reporting completion.
---

# Self Audit Pass

Use this skill after implementation and before final handoff. The goal is to catch obvious defects, missing proof, stale docs, accidental scope drift, and misleading completion claims while the agent still has context to fix them.

## Repo Notes

- Start with `git status --short --branch` and verify the intended CamiFit worktree before editing or staging anything.
- For shared app/KG changes, prefer `scripts/run_monorepo_gates.sh` when time allows; otherwise run the narrow Swift, Python, website, or motion-reference checks tied to the touched files.
- For camera, avatar, motion-guide, or installed-app behavior, treat the visible app/device surface as separate proof from compile or unit-test success.
- Keep CamiFit app-owned state under Application Support distinct from generated Codex logs and temporary proof artifacts.
- Do not claim production motion data or hardware proof from procedural demos, mock traces, or local-only fixture passes.

## Workflow

1. Reconstruct the request.
   - Restate the user's objective, constraints, and expected output.
   - Identify the truth surface: tests, app/browser/device behavior, generated file, deployment, PR checks, or documentation.
   - Note any assumptions that changed during the work.

2. Inspect the actual delta.
   - Read `git status --short` and relevant diffs.
   - Confirm every changed file is connected to the request.
   - Check for accidental secrets, local paths that should not be committed, generated junk, and unrelated rewrites.

3. Review behavior.
   - Trace the main user flow or function call path end to end.
   - For UI work, inspect the running surface when practical; do not rely only on compile success.
   - For automation, verify the event trigger, state persistence, idempotency, and stop conditions.

4. Run focused proof.
   - Use the repo's standard tests, linters, smoke checks, or exact requested command.
   - Add or update tests when the change has meaningful logic, contracts, or regression risk.
   - Keep failed proof visible; fix what is in scope, and report what remains.

5. Repair before reporting.
   - Fix high-confidence defects found during the audit.
   - Update docs or ledgers when the repo uses them as a contract.
   - Do not expand scope into speculative refactors.

6. Handoff honestly.
   - Separate code changes, tests run, visible proof, known gaps, and unverified assumptions.
   - Use `references/audit-report-template.md` when a durable or reviewable audit record is useful.

## Review Prompts

- What would fail in production even if the tests pass?
- What would a reviewer notice in the first five minutes?
- Did the implementation satisfy the user's actual wording, or only a convenient subset?
- Is any proof mock-backed, stale, local-only, or inferred?
- Did any file change because of tooling churn instead of the requested work?

## Stop Conditions

Stop and report instead of hiding uncertainty when proof requires credentials, production access, human taste judgment, unavailable hardware, or public mutation that was not authorized.
