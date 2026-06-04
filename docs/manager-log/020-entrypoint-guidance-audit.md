# Manager Log 020 - Entrypoint Guidance Audit

Date: 2026-06-04
Recorded at: 2026-06-04T18:52:16Z
Role: Manager / Guardian

## Status

The workflow audit verified that `README.md` and `AGENTS.md` existed, while
separate tests checked that those files still pointed future threads to the
agent status command, handoff, stop sentinel, and resume validation flow.

That meant `bash scripts/agent_thread_status.sh` could still report a clean
workflow audit if the entrypoint files drifted but remained present.

## Manager Action

Updated `scripts/audit_autonomous_workflow.sh` to check required entrypoint
guidance content in `AGENTS.md` and `README.md`.

Added workflow-script coverage proving the audit fails when those files exist
but lose the current handoff pointers.

Updated `docs/agent-thread-handoff.md` to reflect the new expected test count
and the stricter workflow-audit responsibility.

## Guardrail

This is process support only. It does not create a resume brief, alter
`GOAL.md`, remove the stop sentinel, start product execution, or change runtime
graph behavior.
