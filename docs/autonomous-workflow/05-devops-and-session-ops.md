# 05 DevOps And Session Ops

Stopped-state safe commands:

```bash
git status --short --branch
git log --oneline -5
bash scripts/agent_thread_status.sh
bash scripts/audit_autonomous_workflow.sh
node scripts/audit_codex_pair_state.mjs
bash scripts/plan_next_resume_brief.sh verified-ontology-lock
bash scripts/stop_codex_goal_loop.sh
```

Resume-brief validation requires a drafted candidate brief:

```bash
bash scripts/validate_resume_brief.sh <planner-next-brief-path>
```

Start/run loop commands require `GOAL.md` to be updated by fresh human
direction so the stop sentinel is absent:

```bash
bash scripts/run_codex_pair_cycle.sh --once --dry-run
bash scripts/run_codex_pair_cycle.sh --once
bash scripts/start_codex_goal_loop.sh --max-cycles 3
```

`scripts/start_codex_goal_loop.sh` refuses to start while `GOAL.md` contains
`<stop-orchestrator/>`.

`scripts/audit_autonomous_workflow.sh` exits non-zero when required workflow
artifacts are missing. `scripts/agent_thread_status.sh` still prints both the
workflow audit and pair-state audit, then exits non-zero if either check fails.

Runtime logs are written under:

```text
/tmp/autonomous-project-workflow/fitgraph/
```

Repo-local marker files:

- `.codex-goal-loop.pid`
- `.codex-executor-session-id`
- `.codex-reviewer-session-id`
- `.codex-executor-latest-log`
- `.codex-reviewer-latest-log`

These marker files are ignored by git.
