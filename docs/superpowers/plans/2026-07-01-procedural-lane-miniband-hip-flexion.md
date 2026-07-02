# Procedural Guide-Motion Lane: standing_miniband_hip_flexion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove the zero-budget procedural lane end-to-end by upgrading the archetype compiler from two-keypose lerp to a keypose-timeline engine and producing a review-ready `standing_miniband_hip_flexion` candidate trace that satisfies the preset's own rep/form rules by construction.

**Architecture:** Add a generic keypose-timeline sampler (circular Catmull-Rom through timed keypose anchors, pinned joints exempt, deterministic micro secondary motion) to `compile_archetype_trace.py`. Convert only the `standing_hip_flexion` archetype to the new path; all other archetypes keep byte-identical legacy output. A new test module validates the generated trace against the preset's signal math (hip-flexion ROM, torso tilt, stance-knee, contact pinning, loop closure). The candidate stays in `dist/` (fail-closed statuses untouched); promotion happens only after human visual review.

**Tech Stack:** Python 3 stdlib only (repo convention: motion scripts have zero third-party deps; tests are `unittest` run directly via `python3 <file>`).

## Global Constraints

- No external motion data enters the repo — authored keyposes only (this is the zero-budget open-source lane; provenance must be "first-party authored keyposes").
- Do NOT change `viewer_status`, `capture.status`, or add `capture.rejection_reason` for standing_miniband_hip_flexion — the profile must stay fail-closed (`is_fail_closed_profile` returns True) so the compiler keeps refusing app-resource output until visual review passes.
- Other archetypes' compiled output must remain byte-identical (regression-tested in Task 1).
- Stage only files listed in each task's commit step — the working tree has unrelated user modifications (release docs, .gitignore, Tests/…MachineChestSupportedRow…) that must never be staged.
- All preset thresholds come from `Sources/CamiFitApp/Resources/Presets/standing_miniband_hip_flexion.json`: rep `down_when: hip_flexion < 125`, `up_when: hip_flexion > 160`, `min_rom_deg: 35`, `down_min_ms: 100`, `bottom_min_ms: 80`; form `knee_drive: hip_flexion <= 115 @ bottom`, `lifted_knee: knee_angle <= 130 @ bottom`, `torso: torso_tilt <= 12`, `stance_leg: stance_knee >= 155`.
- `hip_flexion = angle(left.shoulder, left.hip, left.knee)`; `knee_angle = angle(left.hip, left.knee, left.ankle)`; `torso_tilt = angle_to_vertical(left.shoulder, left.hip)`; `stance_knee = angle(right.hip, right.knee, right.ankle)`. In this trace the working leg is `left.*` (aliased from `primary.*`), stance leg is `right.*`.
- Verification command for every task: `python3 scripts/motion_reference/test_compile_archetype_trace.py` plus (Tasks 3–4) the motion gate block from `scripts/run_monorepo_gates.sh`.

## File Structure

- `scripts/motion_reference/compile_archetype_trace.py` — gains: `catmull_rom_point`, `sample_keypose_timeline`, `KEYPOSE_TIMELINES` registry, secondary-motion helper, `assemble_standing_hip_flexion` (refactor of existing landmark assembly), authored-manifest fields. Legacy factor path untouched for other archetypes.
- `scripts/motion_reference/test_compile_archetype_trace.py` — NEW: unittest module (timeline engine, form validation, legacy regression).
- `scripts/motion_reference/exercise_motion_profiles.json` — contract `reference_policy` text revision + `authoring` block on the standing_miniband_hip_flexion `normalizer`.
- `scripts/motion_reference/render_motion_demo_sheet.py` — NEW (Task 4, only if the existing renderer rejects `motion_demo_pose` format): stdlib SVG contact-sheet renderer.
- `scripts/run_monorepo_gates.sh` — add the new test file to the motion-reference-coverage block.
- `dist/motion-reference/archetype_candidates/standing_miniband_hip_flexion/` — regenerated candidate (gitignored `dist/`; not committed).

---

### Task 1: Keypose-timeline engine with loop-continuous sampling

**Files:**
- Modify: `scripts/motion_reference/compile_archetype_trace.py` (add functions after `smoothstep`, ~line 70)
- Create: `scripts/motion_reference/test_compile_archetype_trace.py`

**Interfaces:**
- Produces: `catmull_rom_point(p0, p1, p2, p3, t) -> float`; `sample_keypose_timeline(anchors: list[dict], poses: dict[str, dict[str, tuple[float, float, float]]], rep_seconds: float, interval_ms: int, pinned: dict[str, tuple[float, float, float]]) -> list[dict[str, dict[str, float]]]` returning per-frame `{joint_name: landmark-dict}` in working-space keys (e.g. `"working.knee"`, `"stance.ankle"`). Anchor schema: `{"at": float in [0,1], "pose": str}`; first and last anchor MUST reference the same pose (loop).
- Consumes: existing `landmark(x, y, z)` helper.

- [ ] **Step 1: Write the failing tests**

Create `scripts/motion_reference/test_compile_archetype_trace.py`:

```python
#!/usr/bin/env python3
"""Unit coverage for the keypose-timeline archetype compiler."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

import compile_archetype_trace as compiler  # noqa: E402

TWO_POSE = {
    "down": {"working.knee": (0.5, 0.7, 0.0)},
    "up": {"working.knee": (0.7, 0.5, 0.0)},
}
TWO_POSE_ANCHORS = [
    {"at": 0.0, "pose": "down"},
    {"at": 0.5, "pose": "up"},
    {"at": 1.0, "pose": "down"},
]


class KeyposeTimelineTests(unittest.TestCase):
    def sample(self, rep_seconds: float = 2.0, interval_ms: int = 100):
        return compiler.sample_keypose_timeline(
            anchors=TWO_POSE_ANCHORS,
            poses=TWO_POSE,
            rep_seconds=rep_seconds,
            interval_ms=interval_ms,
            pinned={"stance.heel": (0.4, 0.87, -0.16)},
        )

    def test_frame_count_comes_from_tempo(self) -> None:
        frames = self.sample(rep_seconds=2.0, interval_ms=100)
        # inclusive end frame so the loop can close: 2.0s / 0.1s = 20 intervals -> 21 frames
        self.assertEqual(len(frames), 21)

    def test_loop_closes_exactly(self) -> None:
        frames = self.sample()
        first = frames[0]["working.knee"]
        last = frames[-1]["working.knee"]
        for axis in ("x", "y", "z"):
            self.assertAlmostEqual(first[axis], last[axis], places=9)

    def test_anchor_poses_are_hit_at_anchor_times(self) -> None:
        frames = self.sample(rep_seconds=2.0, interval_ms=100)
        mid = frames[10]["working.knee"]  # t=0.5 -> "up"
        self.assertAlmostEqual(mid["x"], 0.7, places=9)
        self.assertAlmostEqual(mid["y"], 0.5, places=9)

    def test_pinned_joints_never_move(self) -> None:
        frames = self.sample()
        for frame in frames:
            heel = frame["stance.heel"]
            self.assertEqual((heel["x"], heel["y"], heel["z"]), (0.4, 0.87, -0.16))

    def test_motion_is_smooth_no_frame_snaps(self) -> None:
        frames = self.sample(rep_seconds=2.0, interval_ms=100)
        max_step = 0.0
        for prev, cur in zip(frames, frames[1:]):
            a, b = prev["working.knee"], cur["working.knee"]
            step = ((a["x"] - b["x"]) ** 2 + (a["y"] - b["y"]) ** 2) ** 0.5
            max_step = max(max_step, step)
        # straight-line distance between anchors is ~0.283 over 10 intervals;
        # a smooth curve peaks well under 3x the mean step
        self.assertLess(max_step, 0.085)

    def test_velocity_is_loop_continuous(self) -> None:
        frames = self.sample(rep_seconds=2.0, interval_ms=100)
        a = frames[-2]["working.knee"]
        b = frames[-1]["working.knee"]  # == frames[0]
        c = frames[1]["working.knee"]
        step_in = ((b["x"] - a["x"]) ** 2 + (b["y"] - a["y"]) ** 2) ** 0.5
        step_out = ((c["x"] - b["x"]) ** 2 + (c["y"] - b["y"]) ** 2) ** 0.5
        self.assertLess(abs(step_in - step_out), 0.02)

    def test_holds_are_still(self) -> None:
        anchors = [
            {"at": 0.0, "pose": "down"},
            {"at": 0.4, "pose": "up"},
            {"at": 0.6, "pose": "up"},  # hold
            {"at": 1.0, "pose": "down"},
        ]
        frames = compiler.sample_keypose_timeline(
            anchors=anchors, poses=TWO_POSE, rep_seconds=2.0, interval_ms=100, pinned={}
        )
        # frames at t in [0.4, 0.6] (indices 8..12) must all equal the "up" pose
        for index in range(8, 13):
            knee = frames[index]["working.knee"]
            self.assertAlmostEqual(knee["x"], 0.7, places=6)
            self.assertAlmostEqual(knee["y"], 0.5, places=6)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 scripts/motion_reference/test_compile_archetype_trace.py`
Expected: `AttributeError: module 'compile_archetype_trace' has no attribute 'sample_keypose_timeline'`

- [ ] **Step 3: Implement the timeline engine**

Add to `compile_archetype_trace.py` directly below `smoothstep`:

```python
def catmull_rom_point(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
    t2 = t * t
    t3 = t2 * t
    return 0.5 * (
        (2.0 * p1)
        + (-p0 + p2) * t
        + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
        + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
    )


def _anchor_pose_values(
    anchors: list[dict[str, Any]],
    poses: dict[str, dict[str, tuple[float, float, float]]],
) -> tuple[list[float], dict[str, list[tuple[float, float, float]]]]:
    if anchors[0]["pose"] != anchors[-1]["pose"]:
        raise SystemExit("keypose timeline must start and end on the same pose to loop")
    times = [float(anchor["at"]) for anchor in anchors]
    if times != sorted(times) or times[0] != 0.0 or times[-1] != 1.0:
        raise SystemExit("keypose anchors must be sorted with at=0.0 first and at=1.0 last")
    joint_names = sorted(poses[anchors[0]["pose"]].keys())
    tracks: dict[str, list[tuple[float, float, float]]] = {name: [] for name in joint_names}
    for anchor in anchors:
        pose = poses[anchor["pose"]]
        for name in joint_names:
            tracks[name].append(tuple(float(v) for v in pose[name]))
    return times, tracks


def _sample_track(
    times: list[float],
    points: list[tuple[float, float, float]],
    t: float,
) -> tuple[float, float, float]:
    # circular Catmull-Rom over anchor points; anchors 0 and -1 are the same
    # pose, so neighbours wrap (skipping the duplicated endpoint).
    segment = len(times) - 2
    for index in range(len(times) - 1):
        if t <= times[index + 1]:
            segment = index
            break
    t0, t1 = times[segment], times[segment + 1]
    span = max(t1 - t0, 1e-9)
    local = min(max((t - t0) / span, 0.0), 1.0)
    p1 = points[segment]
    p2 = points[segment + 1]
    p0 = points[segment - 1] if segment > 0 else points[-2]
    p3 = points[segment + 2] if segment + 2 < len(points) else points[1]
    if p1 == p2:  # explicit hold: stay exactly still
        return p1
    return tuple(
        catmull_rom_point(p0[axis], p1[axis], p2[axis], p3[axis], local)
        for axis in range(3)
    )


def sample_keypose_timeline(
    anchors: list[dict[str, Any]],
    poses: dict[str, dict[str, tuple[float, float, float]]],
    rep_seconds: float,
    interval_ms: int,
    pinned: dict[str, tuple[float, float, float]],
) -> list[dict[str, dict[str, float]]]:
    times, tracks = _anchor_pose_values(anchors, poses)
    interval_s = interval_ms / 1000.0
    frame_count = int(round(rep_seconds / interval_s)) + 1
    frames: list[dict[str, dict[str, float]]] = []
    for index in range(frame_count):
        t = min(index * interval_s / rep_seconds, 1.0)
        frame: dict[str, dict[str, float]] = {}
        for name, points in tracks.items():
            if index == frame_count - 1:
                x, y, z = points[0]  # exact loop closure
            else:
                x, y, z = _sample_track(times, points, t)
            frame[name] = landmark(x, y, z)
        for name, point in pinned.items():
            frame[name] = landmark(*point)
        frames.append(frame)
    return frames
```

Note on the smoothness test: Catmull-Rom can overshoot between distant anchors; the two-anchor test path is symmetric, so max step stays bounded. If `test_motion_is_smooth_no_frame_snaps` fails by small margin, clamp overshoot by inserting the midpoint of the two poses as a derived anchor — do NOT loosen the test threshold.

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 scripts/motion_reference/test_compile_archetype_trace.py`
Expected: `OK` (7 tests)

- [ ] **Step 5: Add legacy-output regression test, verify, commit**

Append to the test file (inside the module, new class):

```python
class LegacyArchetypeRegressionTests(unittest.TestCase):
    def test_legacy_archetypes_unchanged(self) -> None:
        profiles = compiler.load_profiles(SCRIPT_DIR / "exercise_motion_profiles.json")
        pike = profiles["bodyweight_pike"]
        frames = compiler.build_frames(pike, interval_ms=100)
        self.assertEqual(len(frames), 17)
        self.assertEqual(frames[0]["source_kind"], "canonical_archetype_trace")
        first = frames[0]["landmarks"]["primary.shoulder"]
        expected = compiler.pike_landmarks(compiler.smoothstep(0))["primary.shoulder"]
        self.assertEqual(first, expected)
```

Run: `python3 scripts/motion_reference/test_compile_archetype_trace.py` → Expected: `OK` (8 tests)

```bash
git add scripts/motion_reference/compile_archetype_trace.py scripts/motion_reference/test_compile_archetype_trace.py
git commit -m "Add keypose-timeline sampler to archetype compiler"
```

---

### Task 2: Authored standing_hip_flexion keyposes with form validation

**Files:**
- Modify: `scripts/motion_reference/compile_archetype_trace.py`
- Modify: `scripts/motion_reference/test_compile_archetype_trace.py`

**Interfaces:**
- Consumes: `sample_keypose_timeline` (Task 1), existing `add_side`, `add_foot`, `landmark`, `angle_degrees`.
- Produces: `KEYPOSE_TIMELINES: dict[str, dict]` registry with key `"standing_hip_flexion"`; `build_frames` routes archetypes present in `KEYPOSE_TIMELINES` through the timeline path and stamps `source_kind: "canonical_archetype_authored"`; `assemble_standing_hip_flexion(working: dict, stance: dict) -> dict[str, dict[str, float]]` producing the full semantic landmark dict (`nose`, `primary.*`, `left.*`, `right.*`, feet).

- [ ] **Step 1: Write the failing form-validation tests**

Append to `test_compile_archetype_trace.py`:

```python
def angle_to_vertical(a: dict[str, float], b: dict[str, float]) -> float:
    import math

    dx = a["x"] - b["x"]
    dy = a["y"] - b["y"]
    return abs(math.degrees(math.atan2(abs(dx), abs(dy))))


class StandingHipFlexionFormTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        profiles = compiler.load_profiles(SCRIPT_DIR / "exercise_motion_profiles.json")
        cls.profile = profiles["standing_miniband_hip_flexion"]
        cls.frames = compiler.build_frames(cls.profile, interval_ms=100)
        cls.marks = [frame["landmarks"] for frame in cls.frames]

    def hip_flexion(self, marks) -> float:
        return compiler.angle_degrees(marks["left.shoulder"], marks["left.hip"], marks["left.knee"])

    def test_source_kind_is_authored(self) -> None:
        self.assertEqual(self.frames[0]["source_kind"], "canonical_archetype_authored")

    def test_rep_thresholds_by_construction(self) -> None:
        values = [self.hip_flexion(m) for m in self.marks]
        self.assertLessEqual(min(values), 112.0)   # knee_drive rule needs <= 115
        self.assertGreaterEqual(max(values), 172.0)  # up_when needs > 160
        self.assertGreaterEqual(max(values) - min(values), 45.0)  # min_rom 35 + margin

    def test_bottom_dwell_satisfies_engine_minimums(self) -> None:
        below_125_ms = sum(100 for m in self.marks if self.hip_flexion(m) < 125.0)
        self.assertGreaterEqual(below_125_ms, 180)  # down_min_ms 100 + bottom_min_ms 80

    def test_lifted_knee_stays_softly_bent_at_bottom(self) -> None:
        for marks in self.marks:
            if self.hip_flexion(marks) <= 115.0:
                knee = compiler.angle_degrees(marks["left.hip"], marks["left.knee"], marks["left.ankle"])
                self.assertLessEqual(knee, 130.0)

    def test_torso_stays_tall_every_frame(self) -> None:
        for marks in self.marks:
            self.assertLessEqual(angle_to_vertical(marks["left.shoulder"], marks["left.hip"]), 12.0)

    def test_stance_leg_stays_tall_every_frame(self) -> None:
        for marks in self.marks:
            stance = compiler.angle_degrees(marks["right.hip"], marks["right.knee"], marks["right.ankle"])
            self.assertGreaterEqual(stance, 155.0)

    def test_stance_contacts_pinned_exactly(self) -> None:
        for key in ("right.heel", "right.foot.index"):
            first = self.marks[0][key]
            for marks in self.marks:
                self.assertEqual(marks[key], first)

    def test_loop_closure_and_length(self) -> None:
        self.assertEqual(self.marks[0], self.marks[-1])
        self.assertGreaterEqual(len(self.frames), 30)  # >= 3.0s rep at 100ms

    def test_bone_lengths_stable(self) -> None:
        def dist(a, b) -> float:
            return ((a["x"] - b["x"]) ** 2 + (a["y"] - b["y"]) ** 2) ** 0.5

        lengths = [dist(m["left.hip"], m["left.knee"]) for m in self.marks]
        spread = (max(lengths) - min(lengths)) / max(sum(lengths) / len(lengths), 1e-9)
        self.assertLess(spread, 0.06)  # thigh length CV well under gate thresholds
```

- [ ] **Step 2: Run tests to verify the new class fails**

Run: `python3 scripts/motion_reference/test_compile_archetype_trace.py`
Expected: `StandingHipFlexionFormTests` failures (`source_kind` still `canonical_archetype_trace`, min hip flexion 105.5 but frame count 17 < 30, dwell 100ms < 180ms). Legacy + timeline tests still pass.

- [ ] **Step 3: Implement keyposes, assembly refactor, and routing**

In `compile_archetype_trace.py`:

3a. Refactor the body of `standing_hip_flexion_landmarks` into an assembly function (keep the old function delegating to it so nothing else breaks):

```python
def assemble_standing_hip_flexion(
    working: dict[str, dict[str, float]],
    stance: dict[str, dict[str, float]],
) -> dict[str, dict[str, float]]:
    landmarks = {"nose": dict(working["nose"])}
    for joint, point in working.items():
        landmarks[f"primary.{joint}"] = dict(point)
    add_side(landmarks, "left", working)
    add_foot(
        landmarks,
        "primary",
        (working["ankle"]["x"] - 0.045, working["ankle"]["y"] + 0.012, 0.05),
        (working["ankle"]["x"] + 0.105, working["ankle"]["y"] + 0.018, 0.06),
        (working["ankle"]["x"], working["ankle"]["y"], 0.05),
    )
    add_foot(
        landmarks,
        "left",
        (working["ankle"]["x"] - 0.045, working["ankle"]["y"] + 0.012, 0.05),
        (working["ankle"]["x"] + 0.105, working["ankle"]["y"] + 0.018, 0.06),
        (working["ankle"]["x"], working["ankle"]["y"], 0.05),
    )
    add_side(landmarks, "right", stance)
    add_foot(landmarks, "right", (0.415, 0.872, -0.16), (0.565, 0.878, -0.15), (0.460, 0.860, -0.16))
    return landmarks
```

3b. Define the keypose set. Working-side joint keys used in poses: `nose, shoulder, elbow, wrist, hip, knee, ankle` (stance side is constant and passed at assembly, not through the sampler). Geometry rules (all keyposes MUST obey them — this is what keeps bone lengths constant):
- hip is fixed at (0.520, 0.500); torso (shoulder) drifts ≤ 0.006 in x (torso rule);
- **thigh length is 0.190**: every knee = hip + 0.190·(sin θ, cos θ) for thigh angle θ from straight-down (y is down-positive);
- **shank length is 0.170**: every ankle = knee + 0.170·(cos φ, sin φ) for shin direction φ;
- θ per pose: stand 0.6°, drive_mid 30°, drive_high 50°, top 72°, lower_high 48°, lower_mid 26° — the extra `drive_high`/`lower_high` pass-through poses keep per-segment Δθ ≤ ~29° so Catmull-Rom chord shrinkage stays under ~4% (the bone-length test allows 6%).

```python
STANDING_HIP_FLEXION_POSES: dict[str, dict[str, tuple[float, float, float]]] = {
    "stand": {
        "nose": (0.520, 0.170, -0.03),
        "shoulder": (0.520, 0.290, 0.0),
        "elbow": (0.490, 0.430, 0.03),
        "wrist": (0.470, 0.550, 0.08),
        "hip": (0.520, 0.500, 0.0),
        "knee": (0.522, 0.690, 0.02),    # θ=0.6°
        "ankle": (0.520, 0.860, 0.05),   # shin ~vertical
    },
    "drive_mid": {
        "nose": (0.517, 0.175, -0.03),
        "shoulder": (0.518, 0.293, 0.0),
        "elbow": (0.485, 0.432, 0.03),
        "wrist": (0.463, 0.550, 0.08),
        "hip": (0.520, 0.500, 0.0),
        "knee": (0.615, 0.664, 0.02),    # θ=30°
        "ankle": (0.591, 0.833, 0.05),   # shin -8° (hangs slightly back)
    },
    "drive_high": {
        "nose": (0.514, 0.179, -0.03),
        "shoulder": (0.516, 0.296, 0.0),
        "elbow": (0.481, 0.433, 0.03),
        "wrist": (0.458, 0.550, 0.08),
        "hip": (0.520, 0.500, 0.0),
        "knee": (0.666, 0.622, 0.02),    # θ=50°
        "ankle": (0.630, 0.788, 0.05),   # shin -12°
    },
    "top": {
        "nose": (0.512, 0.182, -0.03),
        "shoulder": (0.514, 0.298, 0.0),
        "elbow": (0.478, 0.434, 0.03),
        "wrist": (0.455, 0.550, 0.08),
        "hip": (0.520, 0.500, 0.0),
        "knee": (0.701, 0.559, 0.02),    # θ=72° -> hip_flexion ≈ 108.8°
        "ankle": (0.692, 0.729, 0.05),   # knee_angle ≈ 105°
    },
    "lower_high": {
        "nose": (0.515, 0.178, -0.03),
        "shoulder": (0.516, 0.295, 0.0),
        "elbow": (0.482, 0.432, 0.03),
        "wrist": (0.460, 0.550, 0.08),
        "hip": (0.520, 0.500, 0.0),
        "knee": (0.661, 0.627, 0.02),    # θ=48°
        "ankle": (0.632, 0.794, 0.05),   # shin -10°
    },
    "lower_mid": {
        "nose": (0.518, 0.174, -0.03),
        "shoulder": (0.518, 0.292, 0.0),
        "elbow": (0.487, 0.431, 0.03),
        "wrist": (0.465, 0.550, 0.08),
        "hip": (0.520, 0.500, 0.0),
        "knee": (0.603, 0.671, 0.02),    # θ=26°
        "ankle": (0.588, 0.840, 0.05),   # shin -5°
    },
}

STANDING_HIP_FLEXION_STANCE: dict[str, dict[str, float]] = {
    "shoulder": landmark(0.460, 0.300, -0.16),
    "elbow": landmark(0.430, 0.440, -0.16),
    "wrist": landmark(0.410, 0.560, -0.16),
    "hip": landmark(0.460, 0.500, -0.16),
    "knee": landmark(0.462, 0.680, -0.16),
    "ankle": landmark(0.460, 0.860, -0.16),
}

KEYPOSE_TIMELINES: dict[str, dict[str, Any]] = {
    "standing_hip_flexion": {
        "poses": STANDING_HIP_FLEXION_POSES,
        "anchors": [
            {"at": 0.00, "pose": "stand"},
            {"at": 0.06, "pose": "stand"},      # settle hold at top of loop
            {"at": 0.28, "pose": "drive_mid"},
            {"at": 0.40, "pose": "drive_high"},
            {"at": 0.50, "pose": "top"},
            {"at": 0.64, "pose": "top"},        # bottom hold: 0.14 * 3.4s = 476ms
            {"at": 0.76, "pose": "lower_high"},
            {"at": 0.86, "pose": "lower_mid"},
            {"at": 0.96, "pose": "stand"},      # settle hold before loop point
            {"at": 1.00, "pose": "stand"},
        ],
        "rep_seconds": 3.4,
        "assemble": "standing_hip_flexion",
        "sway": {"joints": ("nose", "shoulder", "elbow", "wrist"), "x_amp": 0.0035, "y_amp": 0.0015},
    },
}
```

Verify the geometry hits the thresholds before locking numbers (quick REPL check, angles via `angle_degrees`): stand hip-flexion = angle((0.520,0.290),(0.520,0.500),(0.522,0.690)) ≈ 179.4° (≥172 ✓); top hip-flexion = angle((0.514,0.298),(0.520,0.500),(0.701,0.559)) ≈ 108.8° (≤112 ✓); top knee_angle = angle((0.520,0.500),(0.701,0.559),(0.692,0.729)) ≈ 105° (≤130 ✓); torso tilt at top = atan2-vertical((0.514,0.298),(0.520,0.500)) ≈ 1.7° (≤12 ✓); dwell below 125° ≈ t 0.44→0.70 ≈ 880 ms (≥180 ✓). If any assertion in Step 1's tests still fails, adjust the failing keypose coordinate (knee/ankle, keeping the constant-bone-length rule) — not the test.

3c. Secondary motion + frame builder for timeline archetypes:

```python
def apply_micro_sway(
    pose_frames: list[dict[str, dict[str, float]]],
    sway: dict[str, Any],
) -> list[dict[str, dict[str, float]]]:
    joints = sway["joints"]
    x_amp = float(sway["x_amp"])
    y_amp = float(sway["y_amp"])
    count = max(len(pose_frames) - 1, 1)  # frame 0 == frame -1 must stay identical
    for index, frame in enumerate(pose_frames):
        phase_angle = (index % count) / count * 2.0 * math.pi
        dx = x_amp * math.sin(phase_angle)
        dy = y_amp * math.sin(2.0 * phase_angle)
        for joint in joints:
            if joint in frame:
                frame[joint] = landmark(frame[joint]["x"] + dx, frame[joint]["y"] + dy, frame[joint]["z"])
    return pose_frames


def build_timeline_frames(profile: dict[str, Any], interval_ms: int) -> list[dict[str, Any]]:
    archetype = profile["archetype"]
    spec = KEYPOSE_TIMELINES[archetype]
    raw = sample_keypose_timeline(
        anchors=spec["anchors"],
        poses=spec["poses"],
        rep_seconds=float(spec["rep_seconds"]),
        interval_ms=interval_ms,
        pinned={},
    )
    working_frames = [
        {name: dict(point) for name, point in frame.items()} for frame in raw
    ]
    working_frames = apply_micro_sway(working_frames, spec["sway"])
    frames: list[dict[str, Any]] = []
    for index, working in enumerate(working_frames):
        assembled = assemble_standing_hip_flexion(working, STANDING_HIP_FLEXION_STANCE)
        frames.append(
            {
                "type": "motion_demo_pose",
                "exercise_id": profile["exercise_id"],
                "timestamp_ms": index * interval_ms,
                "image_size": IMAGE_SIZE,
                "phase": f"canonical_{archetype}",
                "source_kind": "canonical_archetype_authored",
                "landmarks": assembled,
            }
        )
    return frames
```

Add `import math` to the module imports. Wire into `build_frames` (top of function):

```python
def build_frames(profile: dict[str, Any], interval_ms: int) -> list[dict[str, Any]]:
    if profile["archetype"] in KEYPOSE_TIMELINES:
        return build_timeline_frames(profile, interval_ms)
    ...  # existing body unchanged
```

Micro-sway loop-closure note: `apply_micro_sway` uses `index % count`, so frame 0 and the final frame (index == count) get identical sway — `test_loop_closure_and_length` (`marks[0] == marks[-1]`) stays green. The working-arm sway moves elbow+wrist+shoulder+nose by the same dx, so shoulder→elbow→wrist bone lengths are unaffected; shoulder↔hip distance varies by ≤0.0035 (torso tilt stays ≤ 2.5°).

- [ ] **Step 4: Run tests to verify everything passes**

Run: `python3 scripts/motion_reference/test_compile_archetype_trace.py`
Expected: `OK` (17 tests). If a form assertion fails, tune the keypose coordinates per 3b's rationale; never loosen a threshold that mirrors the preset.

- [ ] **Step 5: Commit**

```bash
git add scripts/motion_reference/compile_archetype_trace.py scripts/motion_reference/test_compile_archetype_trace.py
git commit -m "Author standing hip flexion via keypose timeline"
```

---

### Task 3: Policy revision, authored manifest fields, and gate wiring

**Files:**
- Modify: `scripts/motion_reference/exercise_motion_profiles.json` (contract block + standing_miniband_hip_flexion normalizer)
- Modify: `scripts/motion_reference/compile_archetype_trace.py` (`write_trace` manifest)
- Modify: `scripts/run_monorepo_gates.sh` (motion-reference-coverage block)
- Modify: `scripts/motion_reference/test_compile_archetype_trace.py` (manifest test)

**Interfaces:**
- Consumes: `build_frames` routing from Task 2.
- Produces: manifest key `source_kind: "canonical_archetype_authored"` and key `authoring` (object) for timeline archetypes; `reference_policy` text that downstream docs/scripts may quote. No machine-read status enums change.

- [ ] **Step 1: Write the failing manifest test**

Append to `test_compile_archetype_trace.py`:

```python
class AuthoredManifestTests(unittest.TestCase):
    def test_manifest_records_authored_provenance(self) -> None:
        import json
        import tempfile

        profiles = compiler.load_profiles(SCRIPT_DIR / "exercise_motion_profiles.json")
        profile = profiles["standing_miniband_hip_flexion"]
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "standing_miniband_hip_flexion.jsonl"
            compiler.write_trace(profile, output, interval_ms=100)
            manifest = json.loads(output.with_suffix(".manifest.json").read_text())
        self.assertEqual(manifest["source_kind"], "canonical_archetype_authored")
        self.assertEqual(manifest["authoring"]["mode"], "keypose_timeline")
        self.assertEqual(manifest["authoring"]["rep_seconds"], 3.4)
        self.assertIn("first-party authored keyposes", manifest["source_label"])
        self.assertIn("visual review", manifest["replacement_plan"])
        self.assertNotIn("Replace with accepted first-party or licensed workout reference footage", manifest["replacement_plan"])
```

Run: `python3 scripts/motion_reference/test_compile_archetype_trace.py`
Expected: FAIL (`source_kind` is `canonical_archetype_trace`, no `authoring` key).

- [ ] **Step 2: Implement manifest changes in `write_trace`**

In `write_trace`, after `normalizer = profile.get("normalizer", {})`, branch on the timeline registry:

```python
    authored = profile.get("archetype") in KEYPOSE_TIMELINES
    if authored:
        spec = KEYPOSE_TIMELINES[profile["archetype"]]
        source_kind = "canonical_archetype_authored"
        source_label = (
            f"{profile['archetype']} first-party authored keyposes "
            "(zero-budget procedural lane; no external motion data)"
        )
        replacement_plan = (
            "Authored canonical candidate; promote only after gallery visual review "
            "passes and the profile exits fail-closed status."
        )
    else:
        spec = None
        source_kind = "canonical_archetype_trace"
        source_label = f"{profile['archetype']} canonical motion profile"
        replacement_plan = (
            "Candidate artifact only; do not bundle as guide motion. Replace with "
            "accepted first-party or licensed workout reference footage before promotion."
        )
```

Use these variables in the manifest dict (replacing the current literals) and add:

```python
    if authored:
        manifest["authoring"] = {
            "mode": "keypose_timeline",
            "rep_seconds": spec["rep_seconds"],
            "anchors": spec["anchors"],
            "license": "First-party authored keyposes; MIT-redistributable; no external motion data.",
        }
```

- [ ] **Step 3: Revise the profile registry**

In `exercise_motion_profiles.json`:

3a. `contract.reference_policy` — replace the existing string with:

```
"reference_policy": "Guide traces may use first-party captures, licensed external workout clips, or first-party authored canonical keypose timelines (zero-budget procedural lane). Every source kind must preserve its full provenance chain (capture/license evidence for footage; keypose/tempo authoring metadata for authored traces) and must pass gallery visual review, engine replay, and installed-app review before promotion."
```

3b. `standing_miniband_hip_flexion.normalizer` — replace the object with:

```json
"normalizer": {
  "status": "implemented",
  "script": "scripts/motion_reference/compile_archetype_trace.py",
  "retarget": "side-view-standing-hip-flexion",
  "cycle_mode": "down-up-down",
  "authoring": {
    "mode": "keypose_timeline",
    "rep_seconds": 3.4,
    "keyposes": ["stand", "drive_mid", "top", "lower_mid"],
    "source": "compile_archetype_trace.py KEYPOSE_TIMELINES['standing_hip_flexion']"
  }
}
```

Leave `viewer_status`, `capture.status`, `qa_gates`, contacts, and everything else in the profile untouched (fail-closed stays intact).

- [ ] **Step 4: Wire the new test into the gates**

In `scripts/run_monorepo_gates.sh`, motion-reference-coverage block: add `scripts/motion_reference/compile_archetype_trace.py` and `scripts/motion_reference/test_compile_archetype_trace.py` to the `python3 -m py_compile` list, and add this line after the two existing test invocations:

```bash
  python3 scripts/motion_reference/test_compile_archetype_trace.py
```

- [ ] **Step 5: Run the full motion gate block to prove no regression**

```bash
python3 -m py_compile scripts/motion_reference/compile_archetype_trace.py scripts/motion_reference/test_compile_archetype_trace.py
python3 scripts/motion_reference/test_compile_archetype_trace.py
scripts/motion_reference/report_motion_pipeline_gaps.py
python3 scripts/motion_reference/test_audit_motion_coverage.py
python3 scripts/motion_reference/test_report_motion_pipeline_gaps.py
scripts/motion_reference/audit_motion_coverage.py --strict --require-trackable-reference-clips --require-guide-ready-inventory
scripts/motion_reference/audit_kg_motion_readiness.py --summary-only
```

Expected: all pass; gap report still shows standing_miniband_hip_flexion as `reference_capture_required` (statuses unchanged — that is correct at candidate stage). If `audit_motion_coverage.py --strict` rejects the `normalizer.status: "implemented"` flip (it may require an accepted capture when a normalizer is implemented), revert 3b's `status` to `"pending_source_preserving_normalizer"`, keep the `authoring` block, and note it in the commit message — the authoritative status flip belongs to the promotion slice.

- [ ] **Step 6: Commit**

```bash
git add scripts/motion_reference/compile_archetype_trace.py scripts/motion_reference/test_compile_archetype_trace.py scripts/motion_reference/exercise_motion_profiles.json scripts/run_monorepo_gates.sh
git commit -m "Accept authored keypose lane in reference policy"
```

---

### Task 4: Regenerate candidate, render review media, hand off for visual review

**Files:**
- Create (likely): `scripts/motion_reference/render_motion_demo_sheet.py`
- Output (not committed; `dist/` and `tmp/` are local-only): `dist/motion-reference/archetype_candidates/standing_miniband_hip_flexion/*`, `tmp/motion-review/standing_miniband_hip_flexion_authored_sheet.svg`

**Interfaces:**
- Consumes: compiler CLI (`--exercise-id standing_miniband_hip_flexion`), Task 2 trace format.
- Produces: candidate JSONL + manifest + an SVG contact sheet for human review.

- [ ] **Step 1: Regenerate the candidate**

```bash
python3 scripts/motion_reference/compile_archetype_trace.py --exercise-id standing_miniband_hip_flexion
```

Expected stdout: `motion-reference compiled=.../dist/motion-reference/archetype_candidates/standing_miniband_hip_flexion/standing_miniband_hip_flexion.jsonl exercise_id=standing_miniband_hip_flexion frames=35`
Sanity: `python3 -c` snippet to print min/max hip-flexion from the emitted JSONL matches Task 2 test bounds (≤112 / ≥172).

- [ ] **Step 2: Try the existing renderer; fall back to an SVG sheet**

```bash
python3 scripts/motion_reference/render_mediapipe_trace_review.py --raw dist/motion-reference/archetype_candidates/standing_miniband_hip_flexion/standing_miniband_hip_flexion.jsonl --output-dir tmp/motion-review/standing_miniband_hip_flexion_authored
```

If it errors on the `motion_demo_pose` format (it expects raw MediaPipe rows), create `render_motion_demo_sheet.py` (stdlib-only) that reads a motion_demo_pose JSONL and writes one SVG contact sheet: one cell per frame (6 columns), each cell drawing circles at each landmark (x*width, y*height) and lines for the segment list `[(shoulder,elbow),(elbow,wrist),(shoulder,hip),(hip,knee),(knee,ankle),(ankle,heel),(heel,foot.index)]` for both `left.*`/`right.*` prefixes (left=working in accent color, right=stance in muted color), frame index + hip-flexion angle labeled per cell. CLI: `--trace <path> --output <path.svg> --columns 6`. Commit this script (it is a reusable review tool):

```bash
git add scripts/motion_reference/render_motion_demo_sheet.py
git commit -m "Add stdlib SVG contact-sheet renderer for motion demo traces"
```

- [ ] **Step 3: Render before/after comparison**

Regenerate the OLD trace for comparison by checking out the pre-change compiler into a temp file (`git show HEAD~3:scripts/motion_reference/compile_archetype_trace.py > /tmp-scratch/old_compiler.py` — use the session scratchpad, and pick the commit just before Task 1's) and running it with `--output-dir <scratchpad>/old_candidate`. Render both sheets.

- [ ] **Step 4: Hand off for the human visual-review gate**

Send both sheets to Kelly with the summary of what changed (frame count 17→35, dwell/tempo, secondary sway, form-by-construction test list) and ask for a pass/fail on the authored candidate. **Do not** bundle into `Sources/CamiFitApp/Resources/MotionDemos/`, do not flip `viewer_status`/`capture.status`, and do not run `--allow-app-resource-output` — promotion is a separate slice that starts only after the visual pass.

---

## Verification checklist (end of plan)

- `python3 scripts/motion_reference/test_compile_archetype_trace.py` → OK (18 tests)
- Motion gate block (Task 3 Step 5 commands) → all pass, gap report unchanged for other exercises
- Candidate JSONL exists with frames ≥ 30, loop-closed, authored manifest
- Review sheet(s) delivered; promotion explicitly deferred to Kelly's visual pass
