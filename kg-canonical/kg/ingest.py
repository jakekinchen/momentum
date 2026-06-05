"""Seed loading boundary for future graph ingestion."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from kg.graph_store import GRAPH_DIR, LocalGraph, load_json, load_local_graph, load_member_graph
from kg.validation import REQUIRED_SEED_FILES


def load_seed_bundle(graph_dir: Path = GRAPH_DIR) -> dict[str, dict[str, Any]]:
    """Load required seed JSON artifacts by file name."""

    return {name: load_json(graph_dir / name) for name in REQUIRED_SEED_FILES}


def load_runtime_graph(graph_dir: Path = GRAPH_DIR) -> LocalGraph:
    """Load the local exercise graph used for deterministic runtime traversal."""

    return load_local_graph(graph_dir / "exercise_kg.seed.json")


def load_member_context_graph(graph_dir: Path = GRAPH_DIR) -> LocalGraph:
    """Load the local member graph used for deterministic fact-card retrieval."""

    return load_member_graph(graph_dir / "member_kg.seed.json")
