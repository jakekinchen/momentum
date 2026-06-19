# Episode-Extreme Form Rules

**Date:** 2026-06-10
**Status:** Implemented
**Scope:** Fix the structural defect that made 13 of 14 guides — including the
protected golden lunge — violate their own form rules, and that cued real
users mid-rep for correct form.

## The defect

`RepStateMachine` keeps phase `bottom` from the down gate until the up gate
fires, so the entire ascent happens "in bottom" (`RepStateMachine.swift`, the
`.bottom` → `.ascending` transition requires `isUp`). Every reach-type rule
("front_knee <= 100 at the bottom") was evaluated instantaneously per frame,
so it necessarily failed during the ascent of every rep, for every user,
including perfect ones. The 2026-06-09 accuracy harness made this visible:
all 13 violated rules were reach-type; every maintain-type rule (torso tilt,
symmetry, body line) passed everywhere.

Two presets compounded it with thresholds stricter than the approved reference
motion itself (lunge depth 100° vs the golden trace's 100.9° filtered minimum).

## The fix

1. **Engine:** `FormRule` gains `evaluation: "instant" | "extreme"`
   (`instant` default). Extreme rules latch: the expectation passes if it was
   satisfied at any frame of the active episode, and one verdict snapshot is
   emitted when the episode ends — pass, or fail with the cue (so coaching
   arrives between reps, not mid-ascent). Mid-episode frames report pending
   (`expectationPassed == nil`), never failure. Failed episodes shorter than
   `min_violation_ms` are discarded as bounces. Implemented in
   `FormRuleEvaluator.updateExtreme`; covered by
   `FormRuleExtremeEvaluationTests`.
2. **Presets:** every reach-type rule is now `extreme`, with thresholds
   calibrated against the shipped guide's bottom-episode extremes (measured
   2026-06-10) and kept strictly inside the rep gates so they retain coaching
   value (the rep counts at the gate; the cue nudges toward reference depth):

   | rule | old expect | new expect | guide extreme | rep gate |
   |---|---|---|---|---|
   | lunge depth | front_knee <= 100 | <= 103 | 100.9 | < 105 |
   | squat depth | knee <= 95 | unchanged | 77.2 | < 100 |
   | pushup depth | elbow <= 95 | <= 90 | 86.0 | < 95 |
   | cable extension_finish | elbow_angle >= 150 | >= 160 | 169.5 | > 150 |
   | pike pike_depth | pike_angle <= 105 | <= 95 | 75.8 | < 105 |
   | miniband knee_drive | hip_flexion <= 125 | <= 115 | 109.2 | < 125 |
   | miniband lifted_knee | knee_angle <= 135 | <= 130 | 120.8 | — |
   | reverse curl curl_height | curl_elbow <= 85 | <= 80 | 76.7 | < 85 |
   | preacher curls curl_depth | curl_elbow <= 85 | <= 70 | 58.3 | < 85 |
   | bench extension_depth | elbow_angle <= 90 | <= 88 | 85.1 | < 90 |
   | suspension press_finish | elbow_angle >= 150 | >= 160 | 175.4 | > 150 |
   | rows row_finish | row_elbow <= 95 | <= 90 | 85.0 | < 95 |
   | rows elbow_path | row_shoulder >= 45 | unchanged | 66.0 | — |

   Thresholds that equaled their rep gate would be vacuous under latching
   (entering bottom already satisfies them), which is why several tightened.
   Maintain-type rules are untouched and stay instant. Presets exist in two
   identical copies (`Presets/` and `Sources/CamiFitApp/Resources/Presets/`)
   and were updated in both.

## Outcome

- All 14 guides replay with **zero** form-rule violations; the accuracy
  baseline ratchet now pins `max_form_violation_frames: 0` everywhere and the
  golden lunge pin asserts a clean exemplar.
- Users no longer receive "Lower into the lunge"-style cues during a correct
  ascent; failed depth now cues exactly once per shallow rep, after the rep.
- Score semantics for reach rules are per-episode (one scored verdict per
  rep) rather than per-frame, which removes the systematic score penalty every
  user paid during every ascent.

## Notes for preset authors

When adding a form rule, choose the evaluation mode deliberately: reach
expectations ("get to depth", "finish the press") must be `extreme`; hold
expectations ("keep the chest tall") stay `instant`. Calibrate reach
thresholds against the exercise's reference guide — `swift test --filter
MotionGuideAccuracy` fails if the shipped guide cannot satisfy them.
