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
