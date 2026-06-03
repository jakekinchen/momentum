# DevOps and Session Ops

## Operational Principle

The workflow should make the loop observable. A human should be able to ask "what is happening?" and get an answer from repo files, logs, commits, and running processes.

## Startup Audit

Before starting or resuming automation:

```bash
git status --short --branch
git log --oneline -5
find . -maxdepth 3 -type f -print | sort
scripts/audit_autonomous_workflow.sh
```

Add project-specific install, lint, test, and smoke commands as soon as they exist.

## Target Automation Scripts

The pair may eventually have these repo-local helpers:

| Script | Purpose |
|---|---|
| `scripts/audit_codex_pair_state.mjs` | Reports branch, dirty state, active mission, session markers, recent logs, live processes, and warnings. |
| `scripts/run_codex_pair_cycle.sh` | Runs exactly one Executor turn then one Reviewer turn, with a lock. |
| `scripts/start_codex_goal_loop.sh` | Starts the supervised loop in a terminal. |
| `scripts/record_latest_codex_session_id.mjs` | Records latest Executor/Reviewer Codex session IDs. |
| `scripts/preflight.sh` | Runs install, lint, typecheck, tests, and smoke checks once they exist. |

Do not build all of these before product work starts. Add them when they reduce real loop friction.

## Script-First Ops

When the workflow repeatedly performs deterministic processing, move the mechanics into a repo-local script and let the agent interpret the bounded output.

Good script candidates:

- Auditing workflow state.
- Extracting latest session markers.
- Summarizing validation logs.
- Checking milestone gates.
- Normalizing generated artifact paths.
- Detecting stale briefs or stop sentinels.

Rules:

- Scripts own parsing, filtering, counting, and deterministic classification.
- Agents own judgment, routing, and communication.
- Prefer bounded stdout with clear warnings. Add machine-readable output only when another script or agent will consume it.
- Do not make the model re-parse large logs or session transcripts when a small extractor would produce the needed facts.

## Dirty Worktree Rule

The supervised loop should refuse to start from a dirty tree unless the Manager or Reviewer explicitly allows it for a known reason.

Dirty-tree exceptions:

- The user has intentionally staged or edited files.
- The current slice requires generated artifacts.
- The Manager is doing workflow-doc edits.

Any exception must be recorded in the session log.

## Logs and Markers

Durable logs:

- `docs/session-logs/`.
- `docs/reviewer-messages/`.
- `docs/manager-log/`.

Temp logs help monitor a running cycle. Durable logs are what future sessions should trust.

## Persistent Role Threads

The loop should reuse one Codex thread per role. The default runner stores local role markers in:

- `.codex-role-sessions/executor.session`
- `.codex-role-sessions/reviewer.session`

`scripts/run_codex_pair_cycle.sh` resumes those markers with `codex exec resume`. If a marker is missing, it seeds the marker from the latest matching JSONL runtime log under `/tmp/autonomous-project-workflow/<repo>/` before creating a new thread. This keeps the Executor and Reviewer as persistent role conversations across milestones instead of opening a new thread for every slice.

Use `scripts/run_codex_pair_cycle.sh --seed-role-sessions` to rebuild markers from existing runtime logs. Use `--reset-role-sessions` only when the saved role thread is intentionally obsolete or cannot be resumed.

## External Services and Spend

Default posture:

- No paid API call without an approved purpose.
- No credential creation without human approval.
- No destructive operation without human approval.

If a model or external service is used, record purpose, inputs, outputs, model/service, and failure behavior in the session log.
