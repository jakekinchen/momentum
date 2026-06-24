# Motion Data Factory Preflight

Date: 2026-06-23

## Purpose

Use this check before promoting motion data from "pose detector produced
landmarks" to a product-trustworthy app guide or validation set.

The command is:

```bash
python3 scripts/motion_reference/preflight_motion_data_factory.py
```

It writes JSON and Markdown reports under `dist/motion-reference/`.

## Promotion Tiers

| Tier | Meaning |
|---|---|
| `recommendation-only` | Exercise can appear in plans, but no motion demo or validation claim is made. |
| `source-candidate` | Source/search evidence exists, but the exercise is not detector-reviewable yet. |
| `detector-reviewable` | Source and detector artifacts exist for review. |
| `avatar-demo-candidate` | A playable or output trace candidate exists, but guide promotion is blocked. |
| `guide-ready` | Current app gate allows the bundled motion guide. |
| `validation-ready` | Guide-ready plus explicit capture-session metadata, detector agreement scorecard, kinematic scorecard, passed visual review, runtime validation clips, and durable source-chain storage. |

## Machine Gates

Every row emits:

- `machine_reasons.guide_ready_blockers`
- `machine_reasons.validation_ready_blockers`
- `factory_concepts.capture_session_metadata`
- `factory_concepts.detector_agreement_scorecard`
- `factory_concepts.kinematic_scorecard`
- `factory_concepts.human_visual_review_decision`
- `factory_concepts.runtime_validation_set`

Existing app-gated guide-ready traces remain `guide-ready` unless a real blocker
is present, but they do not become `validation-ready` until the factory evidence
exists. `reference_capture_required` exercises cannot be promoted by this
preflight.

## Scorecard Contracts

Schema contracts are repo-local:

- `scripts/motion_reference/schemas/capture_session.schema.json`
- `scripts/motion_reference/schemas/detector_agreement_scorecard.schema.json`
- `scripts/motion_reference/schemas/kinematic_scorecard.schema.json`
- `scripts/motion_reference/schemas/visual_review.schema.json`
- `scripts/motion_reference/schemas/motion_data_factory_preflight_report.schema.json`

Capture and review templates are available under
`scripts/motion_reference/templates/`. The first recommended target set is:
`bodyweight_plank`, `machine_chest_supported_row`, and
`standing_miniband_hip_flexion`.

Detector agreement scorecards must include frame coverage, visibility,
detector-disagreement, identity-flip, jitter, and rejected-frame-window fields.
Kinematic scorecards must include limb-length stability, joint-angle limits,
smoothness/jerk, loop boundary delta, contact-lock delta, and phase
monotonicity.

## Expected Current Result

On the current 15-row inventory, the expected safe result is:

- 4 app-gated rows remain `guide-ready`.
- 0 rows are `validation-ready`.
- all `reference_capture_required` rows stay below `guide-ready`.
- rows with failed visual review remain candidate-only until a new passed human
  visual decision is recorded.
