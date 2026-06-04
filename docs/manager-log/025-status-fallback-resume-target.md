# Manager Log 025 - Status Fallback Resume Target

Date: 2026-06-04
Recorded at: 2026-06-04T19:01:40Z
Role: Manager / Guardian

## Status

`scripts/agent_thread_status.sh` normally derives its resume-validation example
from `scripts/plan_next_resume_brief.sh`, but its fallback still returned
`docs/briefs/007-verified-ontology-lock.md`.

If the planner failed or printed no `next brief:` line, the status command
could reintroduce the same stale hardcoded target that the static docs now
avoid.

## Manager Action

Updated `scripts/agent_thread_status.sh` so the fallback target is
`<planner-next-brief-path>`.

Made the status script tolerate a git repository with no commits while printing
the `head:` line, matching the workflow audit's robustness.

Added workflow-script coverage proving the fallback avoids the hardcoded `007`
validation target and still exits cleanly in a minimal stopped-state root.

Updated `docs/agent-thread-handoff.md` to reflect the new expected test count
and fallback behavior.

## Guardrail

This is process support only. It does not create a resume brief, alter
`GOAL.md`, remove the stop sentinel, start product execution, or change runtime
graph behavior.
