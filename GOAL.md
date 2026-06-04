# GOAL

## Active Mission

Build the FitGraph Knowledge Graph module described in
`docs/kg-module-prd.md`: a deterministic typed graph for workout eligibility,
safety filtering, alternatives, decision receipts, and Coach Copilot fact cards.

## Current Milestone

EOD completion and testing

## Current Slice

docs/briefs/010-bad-lower-back-resolver-safety.md

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
