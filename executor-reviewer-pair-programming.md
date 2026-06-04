# Executor / Reviewer / Manager Pair Programming Session

FitGraph uses a supervised Codex pair:

- **Executor** implements one smallest useful, reviewable slice from the active
  brief.
- **Reviewer / Planner** audits the Executor's latest slice, keeps the plan
  coherent, and decides whether to continue, nudge, redirect, stop, or escalate.
- **Manager / Guardian** is the third-party overseer. The manager watches the
  loop, checks evidence quality, challenges false blockers, and edits workflow
  docs or prompts only when the process itself needs correction.

## Core Rule

Repo evidence beats chat memory.

Every autonomous turn should leave enough durable state for a fresh Codex
session to reconstruct:

- active mission;
- slice attempted;
- files changed;
- validation run;
- reviewer decision;
- manager intervention, if any;
- next recommended slice.

## Normal Flow

1. Manager confirms the mission and human constraints.
2. Reviewer writes or refreshes `docs/briefs/NNN-*.md`.
3. Executor reads the active brief, implements one slice, validates it, writes
   `docs/session-logs/NNN-executor-*.md`, and commits scoped files.
4. Reviewer audits the commit and log, then writes
   `docs/reviewer-messages/NNN-*.md`.
5. Manager intervenes only for escalation, context risk, stale planning, false
   blockers, repeated failed cycles, or process optimization.

## Reviewer Decisions

The Reviewer chooses exactly one:

| Decision | Meaning |
|---|---|
| `CONTINUE` | Slice is valid and the next slice is clear. |
| `NUDGE` | Executor needs a tactical correction. |
| `REDIRECT` | The mission, brief, or docs are stale and need durable repair. |
| `STOP` | Mission complete, unsafe to continue, or waiting on a human. |
| `ESCALATE` | Manager or human input is required. |

## Stop Sentinel

When autonomous execution should stop, put this near the top of `GOAL.md`:

```text
<stop-orchestrator/>
```

The Executor must not start a new product slice while the sentinel is present.
Reviewer and Manager may still run to close out, redirect, or ask for a
decision.

## Pair Automation Commands

```bash
node scripts/audit_codex_pair_state.mjs
bash scripts/audit_autonomous_workflow.sh
bash scripts/run_codex_pair_cycle.sh --once --dry-run
bash scripts/run_codex_pair_cycle.sh --once
bash scripts/start_codex_goal_loop.sh --max-cycles 3
bash scripts/stop_codex_goal_loop.sh
```

Use `--dry-run` first. Use an explicit `--max-cycles` for unattended work unless
the intent is to run until `GOAL.md` receives `<stop-orchestrator/>`.

## Manager Oversight Standard

The manager should check:

- current git status and latest commit;
- active brief path in `GOAL.md`;
- latest executor session log;
- latest reviewer decision;
- pair process status;
- whether evidence supports claimed completion;
- whether the next step is small, useful, and PRD-bound.

