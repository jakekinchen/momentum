"""Unit + integration tests for the CamiFit pose worker.

Run with the pre-warmed venv:
    /Users/kelly/Developer/camifit-pose-venv/bin/python -m pytest pose_worker/tests -q
"""
from __future__ import annotations

import os

import pytest

from conftest import MODEL_PATH, STANDING_IMAGE, run_worker

import pose_worker as pw


# --------------------------------------------------------------------------- #
# Schema helpers                                                               #
# --------------------------------------------------------------------------- #
def assert_pose_schema(record: dict) -> None:
    """Assert a `pose` record matches the PoseFrame JSON contract (§7/§8)."""
    assert record["type"] == "pose"
    for key in (
        "frame_id",
        "timestamp_ms",
        "image_size",
        "poses_detected",
        "primary_pose_id",
        "landmarks",
        "world_landmarks",
        "latency_ms",
    ):
        assert key in record, f"missing top-level field: {key}"

    assert isinstance(record["image_size"], list) and len(record["image_size"]) == 2

    if record["poses_detected"] >= 1:
        landmarks = record["landmarks"]
        world = record["world_landmarks"]
        assert len(landmarks) == 33, f"expected 33 landmarks, got {len(landmarks)}"
        assert len(world) == 33, f"expected 33 world_landmarks, got {len(world)}"
        for lm in landmarks:
            for k in ("x", "y", "z", "visibility", "presence"):
                assert k in lm, f"landmark missing {k}"
                assert isinstance(lm[k], (int, float))
        for wl in world:
            assert set(wl.keys()) == {"x", "y", "z"}
            for k in ("x", "y", "z"):
                assert isinstance(wl[k], (int, float))
    else:
        assert record["landmarks"] == []
        assert record["world_landmarks"] == []
        assert record["primary_pose_id"] is None


# --------------------------------------------------------------------------- #
# Health readiness                                                             #
# --------------------------------------------------------------------------- #
def test_health_mock_mode():
    [resp] = run_worker([{"type": "health"}], mode="mock")
    assert resp["type"] == "health"
    assert resp["ok"] is True
    assert resp["pose_ready"] is True
    assert resp["running_mode"] == "VIDEO"
    assert resp["num_poses"] == 2


def test_health_fixture_mode():
    [resp] = run_worker([{"type": "health"}], mode="fixture")
    assert resp["pose_ready"] is True
    assert resp["running_mode"] == "VIDEO"


@pytest.mark.skipif(not pw.mediapipe_available(), reason="mediapipe not installed")
def test_health_mediapipe_mode_with_model():
    if not os.path.exists(MODEL_PATH):
        pytest.skip("model bundle not present")
    [resp] = run_worker([{"type": "health"}], mode="mediapipe", model=MODEL_PATH)
    assert resp["pose_ready"] is True
    assert resp["running_mode"] == "VIDEO"
    assert resp["num_poses"] == 2
    assert "ready" in resp["message"].lower()


def test_health_mediapipe_mode_missing_model():
    """mediapipe mode reports pose_ready=false with a hint when model is absent."""
    bogus = os.path.join(os.path.dirname(MODEL_PATH), "does_not_exist.task")
    [resp] = run_worker([{"type": "health"}], mode="mediapipe", model=bogus)
    # ok=True (the worker is alive), but not ready, with an actionable hint.
    assert resp["ok"] is True
    if not pw.mediapipe_available():
        assert resp["pose_ready"] is False
        assert "mediapipe" in resp["message"].lower()
    else:
        assert resp["pose_ready"] is False
        assert "not found" in resp["message"].lower() or "download" in resp["message"].lower()
        assert bogus in resp["message"] or "pose_landmarker" in resp["message"].lower()


# --------------------------------------------------------------------------- #
# Mock / fixture determinism                                                   #
# --------------------------------------------------------------------------- #
def test_mock_predict_schema():
    [resp] = run_worker(
        [{"type": "predict", "frame_id": 7, "timestamp_ms": 500, "fixture": "standing"}],
        mode="mock",
    )
    assert_pose_schema(resp)
    assert resp["frame_id"] == 7
    assert resp["timestamp_ms"] == 500
    assert resp["poses_detected"] == 1
    assert resp["primary_pose_id"] == "0"


def test_fixture_determinism():
    """Same request -> byte-identical landmarks across runs (minus latency)."""
    req = [{"type": "predict", "frame_id": 1, "timestamp_ms": 100, "fixture": "squat_bottom"}]
    [a] = run_worker(req, mode="fixture")
    [b] = run_worker(req, mode="fixture")
    assert a["landmarks"] == b["landmarks"]
    assert a["world_landmarks"] == b["world_landmarks"]
    assert a["poses_detected"] == b["poses_detected"]


def test_standing_vs_squat_differ():
    """The two fixtures are distinct poses (knee landmark moves)."""
    [standing] = run_worker(
        [{"type": "predict", "frame_id": 1, "timestamp_ms": 1, "fixture": "standing"}],
        mode="fixture",
    )
    [squat] = run_worker(
        [{"type": "predict", "frame_id": 2, "timestamp_ms": 2, "fixture": "squat_bottom"}],
        mode="fixture",
    )
    knee_idx = pw.LANDMARK_NAMES.index("left_knee")
    assert standing["landmarks"][knee_idx] != squat["landmarks"][knee_idx]
    # In a squat the knee drops lower (larger normalized y) than standing.
    assert squat["landmarks"][knee_idx]["y"] > standing["landmarks"][knee_idx]["y"]


def test_fixtures_have_33_landmarks_with_all_fields():
    for name in ("standing", "squat_bottom"):
        fx = pw.FIXTURES[name]
        assert len(fx["landmarks"]) == 33
        assert len(fx["world_landmarks"]) == 33
        for lm in fx["landmarks"]:
            assert set(lm.keys()) == {"x", "y", "z", "visibility", "presence"}
        for wl in fx["world_landmarks"]:
            assert set(wl.keys()) == {"x", "y", "z"}


def test_unknown_fixture_errors_without_crash():
    resps = run_worker(
        [
            {"type": "predict", "frame_id": 1, "timestamp_ms": 1, "fixture": "nope"},
            {"type": "health"},  # loop survives
        ],
        mode="fixture",
    )
    assert resps[0]["type"] == "error"
    assert "nope" in resps[0]["error"]
    assert resps[1]["type"] == "health"


# --------------------------------------------------------------------------- #
# primary_pose_id / poses_detected logic (unit-level)                          #
# --------------------------------------------------------------------------- #
def test_primary_pose_id_none_when_no_poses():
    resp = pw.build_pose_response(
        frame_id=1,
        timestamp_ms=1,
        image_size=(640, 480),
        pose_landmark_sets=[],
        pose_world_landmark_sets=[],
        latency_ms=1.0,
    )
    assert resp["poses_detected"] == 0
    assert resp["primary_pose_id"] is None
    assert resp["landmarks"] == []
    assert resp["world_landmarks"] == []


def test_primary_pose_id_picks_highest_mean_visibility():
    low = [pw._landmark(0.5, 0.5, 0.0, 0.10, 0.10) for _ in range(33)]
    high = [pw._landmark(0.5, 0.5, 0.0, 0.90, 0.90) for _ in range(33)]
    # pose index 1 has higher mean visibility -> primary should be "1".
    resp = pw.build_pose_response(
        frame_id=1,
        timestamp_ms=1,
        image_size=(640, 480),
        pose_landmark_sets=[low, high],
        pose_world_landmark_sets=[[], []],
        latency_ms=1.0,
    )
    assert resp["poses_detected"] == 2
    assert resp["primary_pose_id"] == "1"
    # The emitted landmarks belong to the chosen (high-visibility) pose.
    assert resp["landmarks"][0]["visibility"] == pytest.approx(0.90)


def test_poses_detected_counts():
    one = [pw._landmark(0.5, 0.5, 0.0, 0.9, 0.9) for _ in range(33)]
    resp = pw.build_pose_response(
        frame_id=1,
        timestamp_ms=1,
        image_size=(1, 1),
        pose_landmark_sets=[one],
        pose_world_landmark_sets=[[]],
        latency_ms=0.0,
    )
    assert resp["poses_detected"] == 1
    assert resp["primary_pose_id"] == "0"


# --------------------------------------------------------------------------- #
# Error handling                                                              #
# --------------------------------------------------------------------------- #
def test_invalid_json_does_not_crash_loop():
    # conftest.run_worker only sends valid JSON, so drive the loop directly.
    import io
    import pose_worker as worker

    class Args:
        mode = "fixture"
        model = MODEL_PATH

    out = io.StringIO()
    worker.run_loop(Args(), io.StringIO('{bad\n{"type":"health"}\n'), out)
    lines = [l for l in out.getvalue().splitlines() if l.strip()]
    import json as _json

    parsed = [_json.loads(l) for l in lines]
    assert parsed[0]["type"] == "error"
    assert parsed[1]["type"] == "health"


def test_unknown_request_type_errors():
    [resp] = run_worker([{"type": "frobnicate"}], mode="mock")
    assert resp["type"] == "error"
    assert "frobnicate" in resp["error"]


# --------------------------------------------------------------------------- #
# Real-inference smoke (mediapipe mode)                                        #
# --------------------------------------------------------------------------- #
@pytest.mark.skipif(not pw.mediapipe_available(), reason="mediapipe not installed")
def test_mediapipe_real_inference_smoke():
    if not os.path.exists(MODEL_PATH):
        pytest.skip("model bundle not present")

    requests = [{"type": "health"}]
    if os.path.exists(STANDING_IMAGE):
        requests.append(
            {
                "type": "predict",
                "frame_id": 1,
                "timestamp_ms": 1000,
                "image_path": STANDING_IMAGE,
            }
        )
    resps = run_worker(requests, mode="mediapipe", model=MODEL_PATH)
    health = resps[0]
    assert health["pose_ready"] is True

    if not os.path.exists(STANDING_IMAGE):
        pytest.skip("standing person image not available (download failed); health-only smoke ran")

    pose = resps[1]
    assert_pose_schema(pose)
    # A clear standing person must be detected.
    assert pose["poses_detected"] >= 1, "expected to detect a person in the standing image"
    assert pose["primary_pose_id"] is not None
    # Real landmarks carry nonzero visibility AND presence.
    max_vis = max(lm["visibility"] for lm in pose["landmarks"])
    max_pres = max(lm["presence"] for lm in pose["landmarks"])
    assert max_vis > 0.0
    assert max_pres > 0.0


@pytest.mark.skipif(not pw.mediapipe_available(), reason="mediapipe not installed")
def test_mediapipe_blank_frame_detects_no_pose(tmp_path):
    """Fallback assertion: model loads and runs on a blank frame -> 0 poses."""
    if not os.path.exists(MODEL_PATH):
        pytest.skip("model bundle not present")
    import numpy as np
    from PIL import Image

    blank = tmp_path / "blank.png"
    Image.fromarray(np.zeros((480, 640, 3), dtype=np.uint8)).save(blank)
    [resp] = run_worker(
        [
            {
                "type": "predict",
                "frame_id": 1,
                "timestamp_ms": 1000,
                "image_path": str(blank),
            }
        ],
        mode="mediapipe",
        model=MODEL_PATH,
    )
    assert_pose_schema(resp)
    assert resp["poses_detected"] == 0
    assert resp["primary_pose_id"] is None
