# Manager Log 029 - Stopped-State Manager Protocol

Date: 2026-06-04
Recorded at: 2026-06-04T19:12:15Z
Role: Manager / Guardian

## Status

`docs/autonomous-workflow/06-manager-guardian-protocol.md` described manager
checks and interventions, but it did not explicitly say what a manager-only
support turn may do while `GOAL.md` contains `<stop-orchestrator/>`.

That made stopped-state support less durable for future agent threads, even
though the repo already relied on manager logs for process hardening.

## Manager Action

Added a `Stopped-State Manager Support` section that permits bounded
process-support changes while the stop sentinel is present.

The protocol now states that stopped-state support must not start product
execution, create a resume brief, change runtime graph behavior, or alter
`GOAL.md`.

It also requires durable `docs/manager-log/NNN-*.md` entries for manager support
turns and clarifies that manager-only support does not need executor session
logs or reviewer decisions.

Updated the workflow audit and workflow-script tests to require this protocol
language, including a regression case for a manager protocol file that lacks
the stopped-state support contract.

Updated the handoff test count and audit description for future agent threads.

## Guardrail

This is process support only. It does not create a resume brief, alter
`GOAL.md`, remove the stop sentinel, start product execution, or change runtime
graph behavior.
