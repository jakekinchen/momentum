# FitGraph KG

Deterministic FitGraph knowledge graph module for workout eligibility, safety
filtering, alternatives, decision receipts, and Coach Copilot fact cards.

## Agent Start

Future agent threads should start with:

```bash
bash scripts/agent_thread_status.sh
```

That command prints the current git state, stop-sentinel state, neutral
resume-planning guidance, workflow audit, and Codex pair-state audit. It also
prints a final clean/warning summary. It exits non-zero if the workflow audit
or pair-state audit fails.

If fresh human direction arrives and a future thread needs to draft the next
active brief, first run the dry-run planner:

```bash
bash scripts/plan_next_resume_brief.sh
```

Then rerun it with the human-approved slice slug:

```bash
bash scripts/plan_next_resume_brief.sh verified-ontology-lock
```

Replace the example slug with the human-approved slice name. The command
proposes the next numbered brief path and exact copy command without writing
files or changing `GOAL.md`.

After drafting that brief, validate the candidate file before changing
`GOAL.md`. Use the `next brief:` path printed by the planner:

```bash
bash scripts/validate_resume_brief.sh <planner-next-brief-path>
```

Then read:

- `AGENTS.md`
- `docs/agent-thread-handoff.md`
- `GOAL.md`
- `docs/reviewer-messages/006-review-m5-ontology-sidecar-validation.md`

## Current State

The M0-M5 autonomous plan is complete and stopped. `GOAL.md` contains
`<stop-orchestrator/>`, so do not start a new executor product slice until fresh
human direction removes or replaces the sentinel.

## Safe Checks

```bash
uv run pytest
uv run python -m kg.validation
bash scripts/audit_autonomous_workflow.sh
node scripts/audit_codex_pair_state.mjs
bash scripts/plan_next_resume_brief.sh
```

The resume-brief validator is intentionally not part of the always-safe check
block because it requires a drafted candidate brief path.

## Guardrails

- Runtime safety uses deterministic local graph traversal.
- `MAPS_TO` is ontology audit metadata, not a runtime safety edge.
- Vector search must not enforce safety.
- Do not claim ontology IDs, SNOMED codes, release IDs, access dates, or license
  status are verified unless `graph/ontology-lock.json` contains verified
  pinned values.
