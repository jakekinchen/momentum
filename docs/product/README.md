# Momentum - Your Future Coach Product Overview

**Status:** Current product framing  
**Last updated:** 2026-06-06

Momentum - Your Future Coach is a local-first macOS fitness coach built from a
deterministic movement engine and a FitGraph knowledge-graph reasoning layer. It
is designed to turn a coach request into a safe, explainable workout, then run
supported movements through webcam pose tracking and deterministic exercise
logic.

## What It Does Today

- Builds and launches as a macOS 26 SwiftUI app named
  **Momentum - Your Future Coach**.
- Tracks bodyweight movement locally through the webcam and MediaPipe pose
  worker.
- Runs checked-in exercise presets for squat, lunge, pushup, and plank.
- Counts reps or hold duration, tracks sets, checks form rules, and produces
  local workout summaries.
- Shows avatar guide motion demos for supported app presets.
- Uses KGKit to generate workout recommendations from deterministic graph
  constraints rather than freeform LLM decisions.
- Shows why exercises were selected, filtered, or substituted through reason
  codes, graph paths, and alternatives.
- Answers coach/member context prompts with graph-backed fact cards for Jordan
  Rivera's synthetic assessment data.

## Product Promise

Momentum - Your Future Coach should feel like a personal training surface that
can explain itself. The product is not just a chat UI and not just a rep counter:

- **Watch the workout:** pose tracking and exercise programs own live execution.
- **Respect constraints:** injury, equipment, and prompt exclusions are hard
  deterministic filters.
- **Show the receipt:** every recommendation should expose provenance,
  alternatives, and missing-support states.
- **Stay local-first:** camera tracking and current KG decisions run locally.
- **Be honest about readiness:** recommendation coverage is not the same thing
  as avatar guide or motion-measurement support.

## Current User Story

1. A coach asks for a workout such as:
   `Build a 50-minute lower-body session. Exclude deadlifts. Only DB and KB.`
2. KGKit resolves the constraints and evaluates the generated assessment graph.
3. The app presents a plan card with selected movements, filtered candidates,
   reason codes, graph paths, and alternatives.
4. Motion-ready movements can be added as app routines.
5. The user runs supported presets through the local exercise engine.
6. The coach can ask member-context questions such as:
   `Sleep this week`, `How's adherence trending?`, or
   `Is Jordan at risk of churning?`
7. The Copilot response is a bounded fact card tied to source graph nodes.

## What It Is Not Yet

- Not a production App Store build.
- Not a fully automated Sparkle update distribution.
- Not a production authenticated coach dashboard.
- Not a live medical ontology integration.
- Not a full 50-exercise movement-tracking product.
- Not an LLM-controlled safety system.

## Synthetic Data Boundary

All member data in this repo is synthetic. The assessment snapshot under
`data/golden/candidate-assessment/` is the read-only requirements floor for the
assignment/conformance lane. The repo does not contain real member health data
or PHI.

## Release Evidence

For the current validation and artifact state, read:

- [Release closeout](../release/2026-06-06-conformance-release-closeout.md)
- [Assignment conformance closeout](../briefs/046-assignment-conformance-closeout.md)
- [FitGraph KG README](../../kg-canonical/README.md)
