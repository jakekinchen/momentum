# AGENTS.md

## Agent Thread Orientation

Before starting work, run:

```bash
bash scripts/agent_thread_status.sh
```

Use `docs/agent-thread-handoff.md` for the current stop/resume state. If
`GOAL.md` contains `<stop-orchestrator/>`, do not start a new executor product
slice until fresh human direction removes or replaces the sentinel.

While the stop sentinel is present, manager-only process support may use
`bash scripts/plan_next_manager_log.sh` to choose the next numbered
`docs/manager-log/NNN-*.md` path and must leave a manager log for any
support slice. Before writing a new manager log, review the
`docs/manager-log latest:` line printed by `bash scripts/agent_thread_status.sh`
or `bash scripts/audit_autonomous_workflow.sh`, then run the
`review latest command:` printed by the manager-log planner.

When fresh human direction authorizes a resume, draft the new numbered brief
and run `bash scripts/validate_resume_brief.sh <candidate-brief>` before
updating `GOAL.md`.

## Source of Truth

For FitGraph KG work, follow these files in order:

1. Latest direct user instruction.
2. `docs/kg-module-prd.md`.
3. `GOAL.md`.
4. The active brief named in `GOAL.md`.
5. `executor-reviewer-pair-programming.md`.
6. `docs/autonomous-workflow/`.
7. Existing repo conventions and tests.

## Workflow Rules

- Keep implementation slices small and reviewable.
- Preserve deterministic graph behavior over LLM-driven eligibility.
- Do not use vector search for safety enforcement.
- Do not claim ontology IDs, SNOMED codes, or license status are pinned unless
  `graph/ontology-lock.json` contains the verified value.
- Every autonomous executor turn must leave a session log under
  `docs/session-logs/`.
- Every reviewer turn must leave a decision under `docs/reviewer-messages/`.
- Use exact git add paths for scoped commits.
