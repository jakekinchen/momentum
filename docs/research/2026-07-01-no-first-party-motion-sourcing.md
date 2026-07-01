# Optimal Exercise Guide Motion Without First-Party Recording

Date: 2026-07-01

## Working Conclusion

The 2026-06-23 deep dive recommended a first-party trainer-capture factory.
This document answers the follow-up constraint: **get the best possible guide
visualization for every exercise without recording anyone ourselves.**

The key unlock is architectural, not a single vendor: the app's guide format is
a projected semantic-landmark trace, so **any clean 3D skeletal motion can be
compiled into a guide trace that passes our gates by construction** (bone-length
CV ≈ 0, loop gap = 0, visibility = 1). The problem then reduces to sourcing one
clean 3D motion per exercise, and the market splits cleanly along our own
catalog structure:

1. **Free-space bodyweight movements** are cheaply available as professionally
   captured, commercially licensed mocap (marketplace packs, CMU).
2. **Equipment-coupled isolation movements** (9 of our 15) have essentially
   zero off-the-shelf skeletal coverage anywhere — but they are 1–2
   degree-of-freedom motions that our existing archetype compiler already
   represents well; upgraded procedural authoring is the optimal lane, with
   licensed stock video → commercially-clean HMR (NVIDIA GEM-X) as the
   realism upgrade where good footage exists.
3. **Text-to-motion generation is not viable in 2026** for coaching-grade
   form (legally tainted open models, no equipment awareness).
4. **Commissioned animation (~$75–250/exercise)** is the bounded-cost
   fallback for stragglers, with clean owned provenance.

Recommended split: one generic `compile_motion_clip.py` compiler feeding the
existing QA gates, with four source lanes selected per exercise class, plus two
cross-cutting fixes (equipment props in the avatar scene, horizontal-pose rig
hardening) that no data source can substitute for.

## Constraint and Reframe

Excluded by this document: first-party capture of any kind (webcam, trainer
shoots, multi-view rigs). Allowed: purchased/licensed assets, open datasets
with commercial-clean licenses, offline model inference over licensed footage,
procedural authoring, and paying third parties for animation or custom mocap
(that is their recording, not ours; flagged where used).

Two repo facts make this tractable:

- The shipped `bodyweight_squat` guide is *already* procedural
  (`canonical_squat_landmarks(factor)` in
  `scripts/motion_reference/normalize_squat_trace.py`); only its phase timing
  came from a capture. The best-reviewed motion we ship today is authored, not
  extracted.
- `scripts/motion_reference/compile_archetype_trace.py` already implements 12
  archetypes covering all 15 presets as two-keypose smoothstep loops. They are
  blocked from promotion only by the current
  `reference_policy` ("replace with accepted first-party or licensed workout
  reference footage"), which this strategy revises.

The June review failures also showed that **source quality is not the only
gate**: plank failed with a detached head/neck (rig breaks on horizontal
poses), and suspension press failed for "missing strap/contact context"
(no equipment in the scene). Those are render-side workstreams that stay on
the critical path regardless of motion source.

## What the Market Offers (verified 2026-07-01)

### Lane 1: Licensed marketplace mocap — covers the bodyweight moves, ~$150 total

| Source | Relevant content | License verdict | Price |
|---|---|---|---|
| Fab.com fitness sets ("32/36 Fitness exercices, mocaped", "Exercise animation set 68 HD") | Optical mocap "performed by a professional gym coach" | Fab Standard License: commercial, engine-agnostic, no standalone redistribution | ~$10–60/pack |
| Unity Asset Store: Voxel Vision "GYM Workout" (43 anims: barbell curls/reverse curl, pendlay/meadows rows, squats, decline pushup, side plank) | Nearest-neighbor seeds for equipment moves | Usable outside Unity per Unity support; end product must prevent extraction | $19.99 |
| Unity Asset Store: UhanaMocap "Fitness Mocap Collection" (25 loopable: jumping jack, squat, lunges, curls) | Explicitly loopable mocap | Same as above | $9 |
| Adobe Mixamo | Push-up, squat-family basics | Free commercial use; **service effectively unmaintained (June 2026 outage) — download and archive now** | Free |
| Rokoko Motion Library | À-la-carte pro mocap, skeleton FBX | Commercial use of exports allowed | $3–20/clip |
| CMU Graphics Lab database | Jumping jacks, squats (subj 13/14), lunges (subj 144), stretches | "Free for all uses"; may not resell the data itself | Free |

Not viable in this lane: ActorCore and MoCap Online have excellent mocap but
effectively **zero gym-strength content**; Sketchfab's license bars works whose
"primary value" is the asset (that is exactly a guide motion); MoCap Online
additionally bans AI-powered retargeting over its data; Truebones/free-BVH
archives have untrustworthy provenance.

License obligation for this lane: several EULAs (TurboSquid/CGTrader/Unity)
require shipped assets to be non-trivially extractable. Marketplace-derived
guide traces should ship **compiled/obfuscated (binary or encrypted), not
plain JSONL** in the app bundle.

### Lane 2: Upgraded procedural authoring — optimal for the 9 equipment moves

No marketplace, dataset, or generator has "single-arm chest-supported incline
row" or "standing mini-band hip flexion". But these movements are isolation
patterns: one or two driven joints, everything else pinned by contact policy —
exactly what the exercise contract already specifies (phase driver, ROM,
required contacts). Procedural authoring gives textbook form by construction,
perfect loops, zero license exposure, and it scales to KG archetype variants by
parameter change.

Required upgrade from today's two-keypose lerp: multi-keypose splines with
per-joint easing, tempo/hold timing taken from the preset, slight secondary
motion (breathing sway, wrist micro-adjust) to remove the robotic feel, and
optional physics sanity pass. **Cascadeur Pro ($396/yr, commercially clean,
rent-to-own)** is the recommended authoring/QA companion: AutoPhysics and
collision cleanup directly target our contact/balance gates; author against
blocked-out props and export FBX into the compiler.

Form truth without extraction: license reference video (GymVisual pack or
stock subscriptions) purely as **reviewer reference** for keypose authoring —
watching footage to pose keyframes is not data extraction and keeps this lane
clean even under conservative stock-license readings.

### Lane 3: Licensed stock video → commercially-clean HMR — realism upgrade for niche moves

The June objection to video extraction was MediaPipe-era noise. 2026
state-of-the-art is materially different:

- **NVIDIA GEM/GEM-X (Oct 2025)**: video → camera-space *and world-space*
  motion; Apache-2.0 code, weights under NVIDIA Open Model License with
  training data "owned by NVIDIA or released under permissive licenses, making
  GEM ready for commercial use"; outputs a 77-joint **SOMA** body model owned
  by NVIDIA — **no SMPL entanglement**. Runs offline on Brev; <$1/exercise of
  GPU time. This is the only commercially-clean open extractor found.
- Every other strong model (GVHMR, WHAM, TRAM, PromptHMR, GENMO, MeTRAbs
  weights) is research-only and/or requires SMPL, whose model license bars
  commercial use; MPI's commercial path runs exclusively through Meshcapade —
  which Epic acquired in Feb 2026, shutting its platform. Treat SMPL-based
  models as internal QA comparators only, never as shipped-output producers.
- SaaS fallback for hard clips: **Meshcapade MoCapade** (best foot-locking
  reputation) if their post-acquisition terms allow, else DeepMotion
  Animate 3D (paid tiers include commercial license, quality needs cleanup).
  Move One is iPhone-capture-only, so it is out under our constraint.

Stock-source license verdicts (operative AI/derivative clauses reviewed):

| Source | Verdict |
|---|---|
| Pexels | Cleanest free option: modify + commercial allowed, no AI clause; weak niche coverage |
| Storyblocks | Best paid option: AI restriction expressly scoped to *training*; broad derivative-works grant |
| Envato Elements / Artgrid / Pond5 / Coverr | Usable with care (gray "indirect AI" wording at Envato; verify current texts) |
| Adobe Stock / Pixabay | Gray — broad ML clauses; avoid unless counsel clears |
| Getty/iStock | **Avoid**: bars "any machine learning and/or artificial intelligence purposes" |
| YouTube | **Unusable**: ToS bars downloading/scraping |

Coverage spot-checks: preacher curls are abundant (3,587 Adobe clips; Pond5
has an exact "EZ bar wide grip preacher curl" item), rows and TRX and cable
pushdowns exist; **mini-band hip flexion has no stock coverage** (Lane 2 only).
Prone/bench-lying movements (bench tricep extension, pushup-family) fail every
extractor and SaaS today — keep those procedural/authored.

Legal note (unverified inference from Bikram v. Evolation): functional exercise
movement is likely uncopyrightable, so residual stock risk is contractual, not
copyright. Worth one counsel pass before scaling this lane.

### Lane 4: Commissioned animation — bounded-cost gap-filler

Freelance character animator on our provided rig: **~$75–250 per 3–6 s
exercise loop** (Fiverr/Upwork 2026 rates), ~$5–10k for the full 50-exercise
catalog if we chose to buy everything. MoCap Online custom "Pick-Up Shots"
from $150/clip (+$500 studio fee) for real-mocap gap-fill. Clean, owned
provenance; use for the handful of movements Lanes 1–3 fail.

### Not recommended: generative text-to-motion (2026)

Open models (MDM, MoMask, MotionGPT, T2M-GPT, MotionLCM) are legally poisoned
for commercial use: trained on HumanML3D → AMASS, whose license prohibits
commercial use *and* commercial training. The one commercial-permissive model
(Tencent HY-Motion 1.0) excludes the EU/UK from its license and cannot produce
loops. None accept equipment constraints ("elbow pinned to preacher pad").
DeepMotion SayMotion ($15/mo, clean license, loop tool) may serve as an
optional draft generator for bodyweight moves, saving ~0–30% of authoring time;
no fitness app was found shipping generated guide motion (Muscle & Motion
hand-authors).

## Recommended Architecture

One new generic compiler replaces per-exercise normalizers for non-video
sources and gives every lane the same contract:

```text
source motion (FBX/BVH/GLB mocap | Cascadeur export | GEM-X SOMA joints | archetype keyposes)
  -> retarget onto canonical CamiFit rig (fixed bone lengths, contact pins)
  -> per-exercise virtual camera from profile required_view (side / 45)
  -> project to normalized semantic landmarks (primary/secondary + near/far z)
  -> tempo map from preset (rep seconds, holds) + loop blend (first==last frame)
  -> existing gates: kinematic scorecard, engine replay, gallery visual review
  -> MotionDemos JSONL (+ packed/obfuscated variant for marketplace-derived) + manifest
```

Manifest provenance gains per-source fields: `source_kind` extends to
`licensed_marketplace_mocap | canonical_archetype_authored |
licensed_stock_video_hmr | commissioned_animation`, each with
license/invoice/URL evidence, mirroring the existing first-party chain. The
`reference_policy` line in `exercise_motion_profiles.json` is revised to accept
these kinds, with **gallery visual review remaining the promotion hard gate**.

Cross-cutting (no data source fixes these):

- **Equipment props**: static GLB props per exercise (bench, preacher pad,
  row machine block-out, cable column with wrist-following handle, suspension
  straps, mini-band) keyed by the exercise contract. Directly resolves the
  suspension-press "missing strap/contact context" rejection and makes
  equipment moves legible.
- **Rig hardening for horizontal poses**: fix the segmented-humanoid neck/head
  and forearm attachment behavior that killed plank. Required before plank,
  pike, bench-lying tricep extension, or suspension press can pass review from
  *any* source.

## Per-Exercise Mapping

| Exercise | Lane | Source and notes |
|---|---|---|
| bodyweight_squat | shipped | Keep; optionally upgrade from Fab/Uhana mocap later |
| bodyweight_pushup | shipped | Keep (prone extraction is unsolved anyway) |
| bodyweight_lunge | shipped | Keep; protected golden comparator |
| single_arm_cable_tricep_extension | shipped | Keep |
| bodyweight_jumping_jack | 1 | UhanaMocap loopable ($9) or CMU subj 13/14 (free); replaces the rejected video extraction |
| bodyweight_plank | 2 (+rig fix) | Near-static hold: author directly; verify Fab 68 HD as seed; rig fix is the actual blocker |
| bodyweight_pike | 2 | No marketplace/dataset/stock coverage found |
| machine_chest_supported_row | 2 (+prop) | Seed keyposes from Voxel Vision pendlay/meadows rows; machine block-out prop |
| single_arm_chest_supported_incline_row | 2 (+prop) | No stock confirmed; derive from row archetype, single-arm param |
| bench_lying_single_arm_dumbbell_tricep_extension | 2 (+prop, +rig fix) | Prone defeats extractors; bench prop required |
| single_arm_dumbbell_preacher_curl | 3, else 2 | Stock-rich (thousands of clips) → GEM-X pilot candidate; preacher-pad prop |
| wide_grip_preacher_curl_with_ez_bar | 3, else 2 | Pond5 has the exact clip; same prop |
| resistance_band_reverse_curl | 2 | Band tension invisible to skeleton; simple elbow DOF |
| standing_miniband_hip_flexion | 2 | Confirmed stock gap; archetype candidate already exists in dist/ |
| suspension_tricep_press | 2 (+prop, +rig fix) | No TRX skeletal content anywhere; straps prop resolves prior rejection |

KG tail (50 → beyond): stretches/mobility/jumps → Lane 1 packs (yoga/stretch
mocap is plentiful); equipment variants → Lane 2 archetype parameterization +
prop swaps; unique dynamics (skierg, stair climber) → Lane 3 or Lane 4.

## Costs and Sequencing

Phase 1 (~1 week, <$100): build `compile_motion_clip.py`; buy Uhana + Voxel
Vision; land **jumping jack from purchased mocap** (proves Lane 1) and promote
**standing_miniband_hip_flexion via upgraded archetype** (proves Lane 2 —
candidate exists); revise `reference_policy`; email Fit3D
(`licenses@imar.ro`, subject `[Fit3D Commercial Use]`) and the FLAG3D authors —
those two research datasets contain 37/60 real gym exercises and a purchasable
license could bulk-cover the catalog.

Phase 2 (~2 weeks, <$200): equipment-prop library + horizontal rig fix; land
plank + both preacher curls (one via Storyblocks+GEM-X on Brev as the Lane 3
pilot, one procedural for comparison); archive Mixamo basics.

Phase 3: batch remaining equipment moves procedurally with props; Lane 4
commissions only for reviewer-rejected stragglers. Steady-state cost estimate:
marketplace ~$150 one-time; subscriptions ~$50–130/mo only while Lane 3 runs;
Cascadeur Pro $396/yr; GPU <$1/exercise; commissioning $75–250 per straggler.

## Risks and Open Questions

- Fab listing details came from search snippets (site blocks fetchers):
  confirm per-exercise contents in a browser before purchase.
- GEM-X quality on gym movements is unbenchmarked by us: pilot on preacher
  curl before scaling; keep WHAM/GVHMR as internal-only comparators.
- Stock-license readings ("indirect AI" wording) are our inference: one legal
  review before Lane 3 scales.
- Fit3D/FLAG3D commercial pricing unknown; treat as upside, not plan of
  record. InfiniteRep (CC-BY-4.0 synthetic exercise data) appears abandoned —
  grab a copy if one surfaces.
- Marketplace extraction clauses require packed shipping for derived traces —
  small build change, needed before promoting Lane 1 output.
- QuickMagic advertises no first-party license text; do not rely on it.

## Decision

Adopt the four-lane split with the generic compiler and per-exercise mapping
above. Procedural authoring is promoted from "candidate-only" to a first-class
source lane — the visual-review gallery gate, engine replay, and kinematic
scorecards remain the unchanged promotion authority for every lane.

## Sources

Lane research (2026-07-01, four parallel web sweeps; key primary links):
Fab EULA (fab.com/eula) · Unity cross-engine use (support.unity.com, article
34387186019988) · Voxel Vision anim list (gameassetdeals.com/asset/303410) ·
UhanaMocap (assetstore.unity.com/packages/3d/animations/fitness-mocap-collection-319228)
· Mixamo FAQ (helpx.adobe.com/creative-cloud/faq/mixamo-faq.html) · Rokoko
Motion Library terms (support.rokoko.com) · CMU mocap (mocap.cs.cmu.edu) ·
GEM-X (github.com/NVlabs/GEM-X; huggingface.co/nvidia/GEM-X) · SMPL model
license (smpl.is.tue.mpg.de/modellicense.html) · Meshcapade/Epic
(mpg.de/26082348) · AMASS license (amass.is.tue.mpg.de/license.html) · Fit3D
legal (fit3d.imar.ro/legal) · FLAG3D (andytang15.github.io/FLAG3D) ·
Storyblocks license (storyblocks.com/license/individual-license) · Pexels
license (pexels.com/license) · Getty EULA (gettyimages.com/eula) · SayMotion
(deepmotion.com/saymotion) · HY-Motion license
(huggingface.co/tencent/HY-Motion-1.0) · Cascadeur plans (cascadeur.com/plans)
· MoCap Online licensing/custom (mocaponline.com/pages/licensing,
/pages/custom-animation-services) · TATO video-to-mocap comparison
(tato.studio/best-ai-video-to-mocap) · MoveKit exercise-library comparison
(movekit.com/blog/best-exercise-animation-libraries-2026).
