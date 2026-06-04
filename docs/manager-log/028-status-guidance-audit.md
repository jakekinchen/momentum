# Manager Log 028 - Status Guidance Audit

Date: 2026-06-04
Recorded at: 2026-06-04T19:09:52Z
Role: Manager / Guardian

## Status

`scripts/agent_thread_status.sh` had been updated to keep stopped-state resume
guidance neutral, but `scripts/audit_autonomous_workflow.sh` only guarded the
static docs against stale concrete resume-validation paths.

That left the primary orientation command easier to regress without the
workflow audit noticing.

## Manager Action

Added a `Status resume guidance` audit section that requires the status script
to print the no-argument resume planner dry run and
`bash scripts/validate_resume_brief.sh <planner-next-brief-path>`.

The audit now also rejects the stale concrete
`docs/briefs/007-verified-ontology-lock.md` validation command in the status
script.

Updated workflow-script tests and the minimal workflow fixture to cover the new
audit checks, including a regression case that restores the old concrete
validation target.

Updated the handoff test count and audit description for future agent threads.

## Guardrail

This is process support only. It does not create a resume brief, alter
`GOAL.md`, remove the stop sentinel, start product execution, or change runtime
graph behavior.
