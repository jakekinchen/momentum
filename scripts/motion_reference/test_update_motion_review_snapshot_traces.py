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
                "exercises": [{"id": "bodyweight_test", "trace": [], "frameCount": 0, "durationMs": 0}],
            }

            updated = update_snapshot(snapshot, motion_demos, {"bodyweight_test"})

        self.assertEqual(updated, ["bodyweight_test"])
        exercise = snapshot["exercises"][0]
        self.assertEqual(exercise["frameCount"], 2)
        self.assertEqual(exercise["durationMs"], 120)
        self.assertEqual(exercise["landmarkCount"], 2)
        self.assertEqual(snapshot["summary"]["playableTraces"], 1)
        self.assertNotEqual(snapshot["generatedAt"], "old")


if __name__ == "__main__":
    unittest.main()
