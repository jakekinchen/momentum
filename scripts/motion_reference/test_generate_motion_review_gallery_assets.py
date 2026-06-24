#!/usr/bin/env python3
"""Tests for motion-review gallery asset generation."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from generate_motion_review_gallery_assets import (
    TRACE_REVIEW_FILENAME,
    generated_video_path,
    preferred_review_video,
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
                    {
                        "id": "bodyweight_pike",
                        "media": {
                            "detectorVideoUrl": None,
                            "contactSheetUrl": None,
                            "sourceVideoUrl": "https://videos.pexels.com/example.mp4",
                            "detectorVideoBytes": None,
                            "contactSheetBytes": None,
                            "sourceVideoBytes": 12055907,
                        },
                    },
                ],
            }

            updated = update_snapshot_media(snapshot, public_dir, {"bodyweight_squat"})

        squat_media = updated["exercises"][0]["media"]
        plank_media = updated["exercises"][1]["media"]
        pike_media = updated["exercises"][2]["media"]
        self.assertEqual(squat_media["detectorVideoUrl"], public_media_url("bodyweight_squat"))
        self.assertEqual(squat_media["detectorVideoBytes"], len(b"fake mp4"))
        self.assertIsNone(squat_media["contactSheetUrl"])
        self.assertIsNone(squat_media["sourceVideoUrl"])
        self.assertIsNone(plank_media["detectorVideoUrl"])
        self.assertEqual(pike_media["sourceVideoUrl"], "https://videos.pexels.com/example.mp4")
        self.assertEqual(pike_media["sourceVideoBytes"], 12055907)
        self.assertEqual(updated["summary"]["detectorReviews"], 1)
        self.assertEqual(updated["summary"]["contactSheets"], 0)

    def test_update_snapshot_media_prefers_trace_review_video(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp) / "public"
            skeleton_video = generated_video_path(public_dir, "bodyweight_plank")
            trace_video = generated_video_path(public_dir, "bodyweight_plank", TRACE_REVIEW_FILENAME)
            skeleton_video.parent.mkdir(parents=True)
            skeleton_video.write_bytes(b"small skeleton")
            trace_video.write_bytes(b"larger side by side review")

            snapshot = {
                "summary": {
                    "detectorReviews": 0,
                    "contactSheets": 0,
                },
                "exercises": [
                    {
                        "id": "bodyweight_plank",
                        "media": {
                            "detectorVideoUrl": None,
                            "contactSheetUrl": None,
                            "sourceVideoUrl": None,
                            "detectorVideoBytes": None,
                            "contactSheetBytes": None,
                            "sourceVideoBytes": None,
                        },
                    }
                ],
            }

            updated = update_snapshot_media(snapshot, public_dir, {"bodyweight_plank"})

        plank_media = updated["exercises"][0]["media"]
        self.assertEqual(
            plank_media["detectorVideoUrl"],
            public_media_url("bodyweight_plank", TRACE_REVIEW_FILENAME),
        )
        self.assertEqual(plank_media["detectorVideoBytes"], len(b"larger side by side review"))

    def test_preferred_review_video_falls_back_to_skeleton(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            public_dir = Path(tmp) / "public"
            skeleton_video = generated_video_path(public_dir, "bodyweight_squat")
            skeleton_video.parent.mkdir(parents=True)
            skeleton_video.write_bytes(b"fake mp4")

            preferred = preferred_review_video(public_dir, "bodyweight_squat")

        self.assertIsNotNone(preferred)
        self.assertEqual(preferred[1], "mediapipe_skeleton_review.mp4")


if __name__ == "__main__":
    unittest.main()
