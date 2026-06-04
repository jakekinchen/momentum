# Manager Log 021 - AGENTS Resume Validation Pointer

Date: 2026-06-04
Recorded at: 2026-06-04T18:54:05Z
Role: Manager / Guardian

## Status

The handoff described resume-validation entrypoint guidance for both
`README.md` and `AGENTS.md`, but only `README.md` carried and audited the
`bash scripts/validate_resume_brief.sh ...` pointer.

## Manager Action

Updated `AGENTS.md` so first-hop repo instructions tell future threads to
validate drafted resume briefs before updating `GOAL.md`.

Updated `scripts/audit_autonomous_workflow.sh` so the workflow audit requires
the resume-validation pointer in `AGENTS.md` as well as `README.md`.

Updated workflow-script coverage to assert the new `AGENTS.md` pointer and its
audit failure mode.

Updated `docs/agent-thread-handoff.md` so the workflow-audit description
matches the stricter first-hop contract.

## Guardrail

This is process support only. It does not create a resume brief, alter
`GOAL.md`, remove the stop sentinel, start product execution, or change runtime
graph behavior.
