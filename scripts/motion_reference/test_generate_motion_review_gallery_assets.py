#!/usr/bin/env python3
"""Tests for motion-review gallery asset generation."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from generate_motion_review_gallery_assets import (
    generated_video_path,
    public_media_url,
    update_snapshot_media,
)


class GenerateMotionReviewGalleryAssetsTests(unittest.TestCase):
    def test_update_snapshot_media_sets_public_urls_for_generated_videos(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp) / "public"
            video = generated_video_path(public_dir, "bodyweight_squat")
            video.parent.mkdir(parents=True)
            video.write_bytes(b"fake mp4")

            snapshot = {
                "summary": {
                    "detectorReviews": 0,
                    "contactSheets": 7,
                },
                "exercises": [
                    {
                        "id": "bodyweight_squat",
                        "media": {
                            "detectorVideoUrl": None,
                            "contactSheetUrl": "/old.png",
                            "sourceVideoUrl": "/old.mov",
                            "detectorVideoBytes": None,
                            "contactSheetBytes": 12,
                            "sourceVideoBytes": 13,
                        },
                    },
                    {
                        "id": "bodyweight_plank",
                        "media": {
                            "detectorVideoUrl": "/stale.mp4",
                            "contactSheetUrl": "/old.png",
                            "sourceVideoUrl": "/old.mov",
                            "detectorVideoBytes": 99,
                            "contactSheetBytes": 12,
                            "sourceVideoBytes": 13,
                        },
                    },
                ],
            }

            updated = update_snapshot_media(snapshot, public_dir, {"bodyweight_squat"})

        squat_media = updated["exercises"][0]["media"]
        plank_media = updated["exercises"][1]["media"]
        self.assertEqual(squat_media["detectorVideoUrl"], public_media_url("bodyweight_squat"))
        self.assertEqual(squat_media["detectorVideoBytes"], len(b"fake mp4"))
        self.assertIsNone(squat_media["contactSheetUrl"])
        self.assertIsNone(squat_media["sourceVideoUrl"])
        self.assertIsNone(plank_media["detectorVideoUrl"])
        self.assertEqual(updated["summary"]["detectorReviews"], 1)
        self.assertEqual(updated["summary"]["contactSheets"], 0)


if __name__ == "__main__":
    unittest.main()
