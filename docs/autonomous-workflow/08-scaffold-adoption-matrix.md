# 08 Scaffold Adoption Matrix

| Capability | Status | Notes |
|---|---|---|
| PRD | Present | `docs/kg-module-prd.md` |
| Goal file | Present | `GOAL.md` |
| Active brief | Current | `docs/briefs/014-final-acceptance-closeout.md` |
| Stop sentinel | Present | `<stop-orchestrator/>`; reviewer STOP for final KG-module acceptance closeout; executor product slices are stopped until fresh human direction. |
| Executor log directory | Present | `docs/session-logs/` |
| Reviewer message directory | Present | `docs/reviewer-messages/` |
| Manager log directory | Present | `docs/manager-log/`; review `docs/manager-log latest:` before writing a new support log. |
| Pair runner | Present | `scripts/run_codex_pair_cycle.sh` |
| Background start/stop | Present | `scripts/start_codex_goal_loop.sh`, `scripts/stop_codex_goal_loop.sh` |
| Audit | Present | `scripts/audit_autonomous_workflow.sh`, `scripts/audit_codex_pair_state.mjs` |
| Product implementation | EOD KG-module acceptance stopped | M0-M5 complete; final closeout complete; broad validation and full PRD prompt reachability are green before reviewer STOP. |
