# Manager Log 012 - Safe Command Separation

Date: 2026-06-04
Recorded at: 2026-06-04T18:32:22Z
Role: Manager / Guardian

## Status

The resume-brief validator is useful after a candidate brief exists, but it was
listed next to always-safe orientation commands using the future
`docs/briefs/007-verified-ontology-lock.md` example path. That example file
does not exist while the repository is stopped, so copying the full block would
produce a false failure.

## Manager Action

Separated always-safe orientation commands from resume-only commands in:

- `README.md`
- `docs/agent-thread-handoff.md`
- `docs/autonomous-workflow/05-devops-and-session-ops.md`

Added workflow-script tests that keep:

- README safe checks free of candidate-brief validation commands;
- handoff direct-audit commands free of candidate-brief validation commands;
- DevOps docs clear about stopped-state safe commands versus start/run loop
  commands.

## Guardrail

This does not change `GOAL.md`, create a resume brief, remove the stop sentinel,
start product execution, or change runtime graph behavior.
