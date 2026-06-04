# Manager Log 016 - Planner Validator Step

Date: 2026-06-04
Recorded at: 2026-06-04T18:42:33Z
Role: Manager / Guardian

## Status

`scripts/plan_next_resume_brief.sh` printed the next brief path and `GOAL.md`
follow-up, but it did not print the exact `validate_resume_brief.sh` command
that should run before `GOAL.md` points at the drafted candidate brief.

## Manager Action

Updated the planner to include the candidate resume-brief validation command in
both the required follow-up and validation sections when a concrete slug is
provided. The no-slug dry run now avoids printing a fake placeholder validation
path and tells the agent to rerun with a lowercase slug.

Added workflow-script coverage for both concrete-slug and no-slug planner
output.

## Guardrail

This is process support only. It does not create a resume brief, alter
`GOAL.md`, remove the stop sentinel, start product execution, or change runtime
graph behavior.
