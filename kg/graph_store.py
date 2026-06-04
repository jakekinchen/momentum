"""Local graph artifact inspection for the M0 walking skeleton."""

from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
GRAPH_DIR = REPO_ROOT / "graph"


@dataclass(frozen=True)
class SeedArtifact:
    """Inspection result for a required seed artifact."""

    name: str
    path: Path
    exists: bool
    parse_ok: bool
    status: str
    node_count: int = 0
    edge_count: int = 0
    error: str | None = None


def load_json(path: Path) -> dict[str, Any]:
    """Load one JSON object from disk."""

    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"{path.name} must contain a JSON object")
    return payload


def inspect_seed_artifact(name: str, graph_dir: Path = GRAPH_DIR) -> SeedArtifact:
    """Inspect a seed artifact without treating placeholder data as real graph facts."""

    path = graph_dir / name
    if not path.exists():
        return SeedArtifact(name=name, path=path, exists=False, parse_ok=False, status="missing")

    try:
        payload = load_json(path)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return SeedArtifact(
            name=name,
            path=path,
            exists=True,
            parse_ok=False,
            status="invalid",
            error=str(exc),
        )

    nodes = payload.get("nodes", [])
    edges = payload.get("edges", [])
    node_count = len(nodes) if isinstance(nodes, list) else 0
    edge_count = len(edges) if isinstance(edges, list) else 0
    status = str(payload.get("status", "present"))
    return SeedArtifact(
        name=name,
        path=path,
        exists=True,
        parse_ok=True,
        status=status,
        node_count=node_count,
        edge_count=edge_count,
    )
