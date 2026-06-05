# Manager Log 011 - Resume Brief Validator

Date: 2026-06-04
Recorded at: 2026-06-04T18:23:47Z
Role: Manager / Guardian

## Status

Future threads can now plan the next resume brief path, but a raw copy of the
resume template could still be mistaken for a ready active brief if an agent
updated `GOAL.md` too quickly.

## Manager Action

Added `scripts/validate_resume_brief.sh`, a dry-run validator for candidate
human-approved resume briefs. The validator checks:

- the brief is a numbered non-template file under `docs/briefs/`;
- required resume-template sections are present;
- the Human Direction section has been replaced;
- common template placeholders are gone;
- deterministic graph, ontology-lock, `MAPS_TO`, and vector-safety guardrails
  remain visible;
- the expected validation commands are present.

Updated the agent status command, workflow audit, root README, handoff document,
artifact map, and workflow-script tests so future threads see and verify this
extra guard before changing `GOAL.md`.

## Guardrail

This is process support only. It does not create or activate a brief, remove
the stop sentinel, start product execution, or change runtime graph behavior.
