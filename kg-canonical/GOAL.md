# GOAL

## Active Mission

Finish the broader candidate-assessment dashboard submission on top of the
completed FitGraph Knowledge Graph module. Preserve deterministic typed graph
behavior for workout eligibility, safety filtering, alternatives, decision
receipts, and Coach Copilot fact cards.

## Current Milestone

Assignment conformance closeout

## Current Slice

docs/briefs/017-assignment-conformance-closeout.md

## Stop Conditions

- The PRD acceptance criteria for the current milestone are satisfied and the
  reviewer records `STOP`.
- The reviewer records `ESCALATE` because human product or stack direction is
  required.
- `GOAL.md` contains `<stop-orchestrator/>`.

## Human Constraints

- Do not create external accounts, paid resources, or live ontology downloads.
- Do not claim exact SNOMED CT concept IDs are verified until they are pinned in
  `graph/ontology-lock.json`.
- Treat member safety/equipment constraints as hard blocks.
- Treat member dislikes as soft constraints unless explicitly configured as hard
  blocks.
