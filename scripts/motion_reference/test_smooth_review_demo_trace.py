import json
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path

from smooth_review_demo_trace import load_frames, main


def frame(index: int, x: float) -> dict:
    return {
        "type": "motion_demo_pose",
        "exercise_id": "test_trace",
        "timestamp_ms": index * 100,
        "phase_factor": x,
        "landmarks": {
            "primary.shoulder": {"x": 0.0, "y": 0.0, "z": 0.0, "visibility": 1.0, "presence": 1.0},
            "primary.elbow": {"x": 0.5, "y": 0.0, "z": 0.0, "visibility": 1.0, "presence": 1.0},
            "primary.wrist": {"x": x, "y": 0.0, "z": 0.0, "visibility": 1.0, "presence": 1.0},
        },
    }


class SmoothReviewDemoTraceTests(unittest.TestCase):
    def test_upsamples_smooths_and_preserves_closed_loop(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "source.jsonl"
            output = root / "output.jsonl"
            summary = root / "summary.json"
            frames = [frame(0, 0.0), frame(1, 0.2), frame(2, 1.0), frame(3, 0.2), frame(4, 0.0)]
            source.write_text("\n".join(json.dumps(item) for item in frames) + "\n", encoding="utf-8")

            import sys

            previous_argv = sys.argv
            try:
                sys.argv = [
                    "smooth_review_demo_trace.py",
                    "--input",
                    str(source),
                    "--output",
                    str(output),
                    "--upsample-factor",
                    "2",
                    "--smooth-window",
                    "3",
                    "--summary-output",
                    str(summary),
                ]
                with redirect_stdout(StringIO()):
                    main()
            finally:
                sys.argv = previous_argv

            smoothed = load_frames(output)
            payload = json.loads(summary.read_text(encoding="utf-8"))

        self.assertEqual(len(smoothed), 9)
        self.assertEqual(smoothed[0]["landmarks"], smoothed[-1]["landmarks"])
        self.assertLess(
            payload["after"]["max_landmark_step"]["value"],
            payload["before"]["max_landmark_step"]["value"],
        )
        self.assertEqual(smoothed[0]["timestamp_ms"], 0)
        self.assertEqual(smoothed[-1]["timestamp_ms"], 400)


if __name__ == "__main__":
    unittest.main()
