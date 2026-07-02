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


if __name__ == "__main__":
    unittest.main()
