#!/usr/bin/env python3
"""Freeze the FitGraph seed graph into the Swift kgkit artifact, and (Task 12)
emit golden conformance vectors from the live Python oracle.

Run from the camifit repo root:
    FITGRAPH=/Users/kelly/Developer/fitgraph python3 scripts/gen_kg_conformance_vectors.py
"""
import json, os, sys
from pathlib import Path

FITGRAPH = Path(os.environ.get("FITGRAPH", "/Users/kelly/Developer/fitgraph"))
sys.path.insert(0, str(FITGRAPH))

from kg.graph_store import load_local_graph  # noqa: E402
from kg.safety import load_safety_rules, ONTOLOGY_LOCK_VERSION  # noqa: E402
from kg.validation import GRAPH_VERSION, RULESET_VERSION  # noqa: E402

REPO = Path(__file__).resolve().parents[1]
ARTIFACT = REPO / "Sources/KGKit/Resources/Artifact/kg_artifact.v0.json"


def freeze_artifact() -> None:
    graph = load_local_graph(FITGRAPH / "graph" / "exercise_kg.seed.json")
    rules = load_safety_rules(FITGRAPH / "graph")
    artifact = {
        "graph_version": GRAPH_VERSION,
        "ruleset_version": RULESET_VERSION,
        "ontology_lock_version": ONTOLOGY_LOCK_VERSION,
        "nodes": [
            {"id": n.id, "type": n.type, "label": n.label,
             "aliases": list(n.aliases), "properties": n.properties or {}}
            for n in sorted(graph.nodes.values(), key=lambda x: x.id)
        ],
        "edges": [
            {"source": e.source, "predicate": e.predicate, "target": e.target,
             "properties": e.properties or {}}
            for e in graph.edges
        ],
        "safety_rules": [
            {"id": r.id, "severity": r.severity, "reason_code": r.reason_code,
             "uses_concepts": list(r.uses_concepts), "match": r.match}
            for r in rules
        ],
    }
    ARTIFACT.parent.mkdir(parents=True, exist_ok=True)
    ARTIFACT.write_text(json.dumps(artifact, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {ARTIFACT.relative_to(REPO)}: "
          f"{len(artifact['nodes'])} nodes / {len(artifact['edges'])} edges / "
          f"{len(artifact['safety_rules'])} rules")


if __name__ == "__main__":
    freeze_artifact()
