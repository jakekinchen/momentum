"""Shared pytest fixtures/paths for the pose worker tests."""
from __future__ import annotations

import json
import os
import subprocess
import sys
from typing import Any, Dict, List

import pytest

# Make `import pose_worker` resolve to pose_worker/pose_worker.py.
POSE_WORKER_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if POSE_WORKER_DIR not in sys.path:
    sys.path.insert(0, POSE_WORKER_DIR)

WORKER_SCRIPT = os.path.join(POSE_WORKER_DIR, "pose_worker.py")
MODEL_PATH = os.path.join(POSE_WORKER_DIR, "models", "pose_landmarker_lite.task")
STANDING_IMAGE = os.path.join(POSE_WORKER_DIR, "models", "test_assets", "standing.jpg")
PYTHON = sys.executable


def run_worker(requests: List[Dict[str, Any]], *, mode: str, model: str | None = None) -> List[Dict[str, Any]]:
    """Drive pose_worker.py as a subprocess over JSONL and collect responses."""
    cmd = [PYTHON, WORKER_SCRIPT, "--mode", mode]
    if model is not None:
        cmd += ["--model", model]
    stdin = "".join(json.dumps(r) + "\n" for r in requests)
    proc = subprocess.run(
        cmd,
        input=stdin,
        capture_output=True,
        text=True,
        timeout=120,
    )
    lines = [l for l in proc.stdout.splitlines() if l.strip()]
    return [json.loads(l) for l in lines]


@pytest.fixture(scope="session")
def model_path() -> str:
    return MODEL_PATH


@pytest.fixture(scope="session")
def standing_image() -> str:
    return STANDING_IMAGE
