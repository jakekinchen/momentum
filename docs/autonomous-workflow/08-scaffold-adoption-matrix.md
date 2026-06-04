# 08 Scaffold Adoption Matrix

| Capability | Status | Notes |
|---|---|---|
| PRD | Present | `docs/kg-module-prd.md` |
| Goal file | Present | `GOAL.md` |
| Active brief | Current | `docs/briefs/006-m5-ontology-sidecar-validation.md` |
| Stop sentinel | Present | `GOAL.md` contains `<stop-orchestrator/>`; executor product slices are stopped until fresh human direction. |
| Executor log directory | Present | `docs/session-logs/` |
| Reviewer message directory | Present | `docs/reviewer-messages/` |
| Manager log directory | Present | `docs/manager-log/`; review `docs/manager-log latest:` before writing a new support log. |
| Pair runner | Present | `scripts/run_codex_pair_cycle.sh` |
| Background start/stop | Present | `scripts/start_codex_goal_loop.sh`, `scripts/stop_codex_goal_loop.sh` |
| Audit | Present | `scripts/audit_autonomous_workflow.sh`, `scripts/audit_codex_pair_state.mjs` |
| Product implementation | M0-M5 complete | The autonomous M0-M5 plan is stopped; remaining production work requires fresh human direction and a new validated brief. |
