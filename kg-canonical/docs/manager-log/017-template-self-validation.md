# Manager Log 017 - Template Self-Validation

Date: 2026-06-04
Recorded at: 2026-06-04T18:44:46Z
Role: Manager / Guardian

## Status

The resume planner printed the correct `validate_resume_brief.sh` command, but
the human-approved resume template's checklist still moved from copying the
template directly to updating `GOAL.md`.

## Manager Action

Updated `docs/briefs/000-template-human-approved-resume.md` so the checklist
requires running `bash scripts/validate_resume_brief.sh ...` on the drafted
brief before updating `GOAL.md`.

Updated `scripts/validate_resume_brief.sh` so candidate resume briefs must carry
that self-validation command, and added workflow-script coverage proving a
candidate without it fails validation.

## Guardrail

This is process support only. It does not create a resume brief, alter
`GOAL.md`, remove the stop sentinel, start product execution, or change runtime
graph behavior.
