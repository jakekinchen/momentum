import json
import tempfile
import unittest
from pathlib import Path

from update_motion_review_snapshot_traces import update_snapshot


class UpdateMotionReviewSnapshotTracesTests(unittest.TestCase):
    def test_replaces_trace_and_stats_for_matching_exercise(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            motion_demos = root / "MotionDemos"
            motion_demos.mkdir()
            (motion_demos / "bodyweight_test.jsonl").write_text(
                "\n".join(
                    [
                        json.dumps(
                            {
                                "timestamp_ms": 0,
                                "image_size": [1280, 720],
                                "landmarks": {"primary.wrist": {"x": 0.1, "y": 0.2, "z": 0.0}},
                            }
                        ),
                        json.dumps(
                            {
                                "timestamp_ms": 120,
                                "image_size": [1280, 720],
                                "landmarks": {
                                    "primary.wrist": {"x": 0.2, "y": 0.3, "z": 0.0},
                                    "primary.elbow": {"x": 0.3, "y": 0.4, "z": 0.0},
                                },
                            }
                        ),
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            snapshot = {
                "generatedAt": "old",
                "summary": {"playableTraces": 0},
                "exercises": [
                    {
                        "id": "bodyweight_test",
                        "gateStatus": "reference_capture_required",
                        "acceptanceStatus": "pending_reference_capture",
                        "trace": [],
                        "frameCount": 0,
                        "durationMs": 0,
                        "media": {
                            "detectorVideoUrl": "/motion-review-assets/bodyweight_test/mediapipe_skeleton_review.mp4",
                            "contactSheetUrl": None,
                            "sourceVideoUrl": None,
                        },
                        "missing": ["playable JSONL", "review video"],
                        "nextReview": "Capture or normalize a playable JSONL trace before judging the app motion.",
                        "factory": {
                            "promotionTier": "source-candidate",
                            "tierIndex": 1,
                            "guideReady": False,
                            "validationReady": False,
                            "guideReadyBlockers": ["reference_capture_required_gate"],
                            "validationReadyBlockers": ["not_guide_ready"],
                            "warnings": ["playable JSONL", "review video"],
                            "nextAction": "Capture or normalize a playable JSONL trace before judging the app motion.",
                            "currentSignals": {"playableJsonl": False},
                        },
                    }
                ],
            }

            updated = update_snapshot(snapshot, motion_demos, {"bodyweight_test"})

        self.assertEqual(updated, ["bodyweight_test"])
        exercise = snapshot["exercises"][0]
        self.assertEqual(exercise["frameCount"], 2)
        self.assertEqual(exercise["durationMs"], 120)
        self.assertEqual(exercise["landmarkCount"], 2)
        self.assertNotIn("playable JSONL", exercise["missing"])
        self.assertNotIn("review video", exercise["missing"])
        self.assertEqual(
            exercise["nextReview"],
            "Review the trace media, then either promote after strict provenance or keep recommendation-only.",
        )
        self.assertEqual(exercise["factory"]["promotionTier"], "avatar-demo-candidate")
        self.assertTrue(exercise["factory"]["currentSignals"]["playableJsonl"])
        self.assertEqual(snapshot["summary"]["playableTraces"], 1)
        self.assertEqual(snapshot["summary"]["tierCounts"]["avatar-demo-candidate"], 1)
        self.assertNotEqual(snapshot["generatedAt"], "old")


if __name__ == "__main__":
    unittest.main()
