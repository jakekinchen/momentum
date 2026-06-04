"""Deterministic health checks for the FitGraph KG walking skeleton."""

from __future__ import annotations

from dataclasses import asdict
import json
from pathlib import Path
import sys
from typing import Any

from kg.graph_store import GRAPH_DIR, SeedArtifact, inspect_seed_artifact, load_json


GRAPH_VERSION = "fitgraph-kg-m0-skeleton-v0"
RULESET_VERSION = "ruleset-m0-placeholder-v0"
REQUIRED_SEED_FILES: tuple[str, ...] = (
    "exercise_kg.seed.json",
    "member_kg.seed.json",
    "ontology_mappings.seed.json",
    "safety_rules.seed.json",
    "provenance_schema.json",
    "ontology-lock.json",
)


def _artifact_payload(artifact: SeedArtifact) -> dict[str, Any]:
    payload = asdict(artifact)
    payload["path"] = str(artifact.path)
    return payload


def _ontology_lock_metadata(graph_dir: Path) -> dict[str, Any]:
    path = graph_dir / "ontology-lock.json"
    if not path.exists():
        return {
            "ontology_lock_version": "missing",
            "ontology_status": "missing",
            "verified": False,
        }

    payload = load_json(path)
    return {
        "ontology_lock_version": str(payload.get("ontology_lock_version", "unknown")),
        "ontology_status": str(payload.get("status", "unknown")),
        "verified": bool(payload.get("verified", False)),
    }


def health_summary(graph_dir: Path = GRAPH_DIR) -> dict[str, Any]:
    """Return deterministic seed-file and version health for the local graph."""

    artifacts = [inspect_seed_artifact(name, graph_dir) for name in REQUIRED_SEED_FILES]
    seed_files = {artifact.name: _artifact_payload(artifact) for artifact in artifacts}
    validation_errors = [
        f"{artifact.name}: {artifact.error or artifact.status}"
        for artifact in artifacts
        if not artifact.exists or not artifact.parse_ok
    ]

    try:
        ontology_metadata = _ontology_lock_metadata(graph_dir)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        ontology_metadata = {
            "ontology_lock_version": "invalid",
            "ontology_status": "invalid",
            "verified": False,
        }
        validation_errors.append(f"ontology-lock.json: {exc}")

    return {
        "graph_version": GRAPH_VERSION,
        "ruleset_version": RULESET_VERSION,
        **ontology_metadata,
        "validation_status": "pass" if not validation_errors else "fail",
        "validation_errors": validation_errors,
        "graph_dir": str(graph_dir),
        "required_seed_count": len(REQUIRED_SEED_FILES),
        "present_seed_count": sum(1 for artifact in artifacts if artifact.exists),
        "parseable_seed_count": sum(1 for artifact in artifacts if artifact.parse_ok),
        "node_count": sum(artifact.node_count for artifact in artifacts),
        "edge_count": sum(artifact.edge_count for artifact in artifacts),
        "seed_files": seed_files,
    }


def main() -> int:
    """Print graph health as JSON and return non-zero on failed validation."""

    summary = health_summary()
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0 if summary["validation_status"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
