# 05 DevOps And Session Ops

Useful commands:

```bash
git status --short --branch
git log --oneline -5
bash scripts/agent_thread_status.sh
bash scripts/audit_autonomous_workflow.sh
node scripts/audit_codex_pair_state.mjs
bash scripts/run_codex_pair_cycle.sh --once --dry-run
bash scripts/run_codex_pair_cycle.sh --once
bash scripts/start_codex_goal_loop.sh --max-cycles 3
bash scripts/stop_codex_goal_loop.sh
```

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
