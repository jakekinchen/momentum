# Manager Log 019 - Resume Checklist Target

Date: 2026-06-04
Recorded at: 2026-06-04T18:49:52Z
Role: Manager / Guardian

## Status

The resume validator required the exact self-validation command to appear in a
candidate brief, but it did not require that command to appear in the
`## Resume Checklist` section where future agents are directed before updating
`GOAL.md`.

## Manager Action

Updated `scripts/validate_resume_brief.sh` to extract `## Resume Checklist` and
require `bash scripts/validate_resume_brief.sh <candidate-brief>` inside that
section.

Added workflow-script coverage proving:

- valid candidate briefs pass the checklist-specific target check;
- missing self-validation commands fail the checklist-specific check;
- stale copied self-validation targets fail the checklist-specific check;
- a candidate with the exact command elsewhere in the brief but not in
  `## Resume Checklist` fails validation.

Updated `docs/agent-thread-handoff.md` to reflect the new expected test count
and checklist-specific validation rule.

## Guardrail

This is process support only. It does not create a resume brief, alter
`GOAL.md`, remove the stop sentinel, start product execution, or change runtime
graph behavior.
