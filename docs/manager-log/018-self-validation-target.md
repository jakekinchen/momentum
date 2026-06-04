# Manager Log 018 - Self-Validation Target

Date: 2026-06-04
Recorded at: 2026-06-04T18:47:50Z
Role: Manager / Guardian

## Status

The resume validator required candidate briefs to include a
`bash scripts/validate_resume_brief.sh ...` command, but it did not verify that
the command targeted the same candidate file being validated.

## Manager Action

Updated `scripts/validate_resume_brief.sh` to require the self-validation
command to target the candidate brief path passed to the validator.

Added workflow-script coverage proving:

- a valid candidate reports that the self-validation command targets itself;
- a missing self-validation command fails both presence and target checks;
- a copied brief with a stale self-validation target fails validation.

Updated `docs/agent-thread-handoff.md` to reflect the new expected test count
and the stricter candidate-brief validation rule.

## Guardrail

This is process support only. It does not create a resume brief, alter
`GOAL.md`, remove the stop sentinel, start product execution, or change runtime
graph behavior.
