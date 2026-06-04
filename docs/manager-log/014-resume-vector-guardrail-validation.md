# Manager Log 014 - Resume Vector Guardrail Validation

Date: 2026-06-04
Recorded at: 2026-06-04T18:37:34Z
Role: Manager / Guardian

## Status

The resume-brief validator checked that a candidate brief mentioned `vector`,
but that was too weak. A brief could mention vector search in an unsafe way and
still satisfy the old check.

## Manager Action

Tightened `scripts/validate_resume_brief.sh` so candidate resume briefs must
include an explicit safety guardrail such as `Vector search must not enforce
safety` or equivalent stopped-template wording, even when that wording wraps
across Markdown lines. Added rejection checks for affirmative vector-safety
enforcement language.

Added workflow-script coverage proving a candidate brief that says `Use vector
search for safety enforcement` fails validation.

## Guardrail

This is process support only. It does not alter `GOAL.md`, remove the stop
sentinel, start product execution, or change runtime graph behavior.
