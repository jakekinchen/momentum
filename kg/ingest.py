"""Seed loading boundary for future graph ingestion."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from kg.graph_store import GRAPH_DIR, load_json
from kg.validation import REQUIRED_SEED_FILES


def load_seed_bundle(graph_dir: Path = GRAPH_DIR) -> dict[str, dict[str, Any]]:
    """Load required seed JSON artifacts by file name."""

    return {name: load_json(graph_dir / name) for name in REQUIRED_SEED_FILES}
