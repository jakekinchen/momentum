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

from kg.assessment_import import build_assessment_import_artifacts  # noqa: E402
from kg.graph_store import load_local_graph  # noqa: E402
from kg.safety import load_safety_rules, ONTOLOGY_LOCK_VERSION  # noqa: E402
from kg.validation import GRAPH_VERSION, RULESET_VERSION  # noqa: E402

REPO = Path(__file__).resolve().parents[1]
ARTIFACT = REPO / "Sources/KGKit/Resources/Artifact/kg_artifact.v0.json"
ASSESSMENT_ARTIFACT = REPO / "Sources/KGKit/Resources/Artifact/kg_artifact.assessment.v0.json"
ASSESSMENT_MEMBER_GRAPH = REPO / "Sources/KGKit/Resources/Artifact/assessment_member_kg.generated.json"


def encoded_rules() -> list[dict]:
    rules = load_safety_rules(FITGRAPH / "graph")
    return [
        {"id": r.id, "severity": r.severity, "reason_code": r.reason_code,
         "uses_concepts": list(r.uses_concepts), "match": r.match}
        for r in rules
    ]


def freeze_artifact() -> None:
    graph = load_local_graph(FITGRAPH / "graph" / "exercise_kg.seed.json")
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
        "safety_rules": encoded_rules(),
    }
    ARTIFACT.parent.mkdir(parents=True, exist_ok=True)
    ARTIFACT.write_text(json.dumps(artifact, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {ARTIFACT.relative_to(REPO)}: "
          f"{len(artifact['nodes'])} nodes / {len(artifact['edges'])} edges / "
          f"{len(artifact['safety_rules'])} rules")


def freeze_assessment_artifact() -> None:
    artifacts = build_assessment_import_artifacts()
    exercise_graph = artifacts.exercise_graph
    summary = artifacts.conformance_summary
    source = dict(exercise_graph.get("source") or {})
    artifact = {
        "artifact_kind": "assignment_assessment_runtime",
        "graph_version": exercise_graph["graph_version"],
        "ruleset_version": RULESET_VERSION,
        "ontology_lock_version": ONTOLOGY_LOCK_VERSION,
        "generated_graph_version": exercise_graph["graph_version"],
        "source_snapshot_commit": summary["source_snapshot_commit"],
        "source": source,
        "source_hashes": {
            "exercises_sha256": summary["exercise_source_sha256"],
            "member_context_sha256": summary["member_source_sha256"],
        },
        "conformance_summary": summary,
        "nodes": exercise_graph["nodes"],
        "edges": exercise_graph["edges"],
        "safety_rules": encoded_rules(),
    }
    ASSESSMENT_ARTIFACT.parent.mkdir(parents=True, exist_ok=True)
    ASSESSMENT_ARTIFACT.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    ASSESSMENT_MEMBER_GRAPH.write_text(json.dumps(artifacts.member_graph, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {ASSESSMENT_ARTIFACT.relative_to(REPO)}: "
          f"{len(artifact['nodes'])} nodes / {len(artifact['edges'])} edges / "
          f"{len(artifact['safety_rules'])} rules")
    print(f"wrote {ASSESSMENT_MEMBER_GRAPH.relative_to(REPO)}: "
          f"{len(artifacts.member_graph['nodes'])} nodes / {len(artifacts.member_graph['edges'])} edges")


from kg.constraints import ResolvedConstraint  # noqa: E402
from kg.safety import evaluate_candidates  # noqa: E402

VECTORS = REPO / "Tests/KGKitTests/Fixtures/conformance/safety_vectors.json"


def _c(**kw) -> ResolvedConstraint:
    base = dict(constraint_type="", value="", hard=False, source_text="")
    base.update(kw)
    return ResolvedConstraint(**base)


def emit_vectors() -> None:
    graph = load_local_graph(FITGRAPH / "graph" / "exercise_kg.seed.json")
    rules = load_safety_rules(FITGRAPH / "graph")
    jordan_equipment = ["Dumbbell", "Kettlebell", "Yoga Mat"]
    scenarios = [
        {"name": "knee_restriction", "available_equipment": jordan_equipment,
         "constraints": [_c(constraint_type="BodyRegion", value="left_knee", hard=True, source_text="left knee")]},
        {"name": "no_barbell", "available_equipment": jordan_equipment,
         "constraints": [_c(constraint_type="Equipment", value="barbell", hard=True, negated=True, source_text="no barbell")]},
        {"name": "exclude_deadlifts", "available_equipment": jordan_equipment,
         "constraints": [_c(constraint_type="ExerciseFamily", value="deadlift_family", hard=True, negated=True, source_text="exclude deadlifts")]},
        {"name": "clean", "available_equipment": jordan_equipment, "constraints": []},
    ]
    vectors = []
    for sc in scenarios:
        receipts = evaluate_candidates(
            available_equipment=sc["available_equipment"],
            constraints=tuple(sc["constraints"]), graph=graph, safety_rules=rules)
        for r in receipts:
            vectors.append({
                "scenario": sc["name"],
                "input": {
                    "available_equipment": sc["available_equipment"],
                    "constraints": [
                        {"constraint_type": c.constraint_type, "value": c.value, "hard": c.hard,
                         "source_text": c.source_text, "negated": c.negated} for c in sc["constraints"]
                    ],
                    "exercise_id": r.exercise_id,
                },
                "expected": {
                    "decision": r.decision, "primary_severity": r.primary_severity,
                    "reason_codes": list(r.reason_codes), "primary_reason_code": r.primary_reason_code,
                    "graph_paths": list(r.graph_paths), "constraint_fingerprint": r.constraint_fingerprint,
                    "graph_version": r.graph_version, "ruleset_version": r.ruleset_version,
                    "ontology_lock_version": r.ontology_lock_version,
                },
            })
    VECTORS.parent.mkdir(parents=True, exist_ok=True)
    VECTORS.write_text(json.dumps({"vectors": vectors}, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {VECTORS.relative_to(REPO)}: {len(vectors)} vectors")


from kg.resolver import resolve_text  # noqa: E402

RESOLVE_VECTORS = REPO / "Tests/KGKitTests/Fixtures/conformance/resolve_vectors.json"

RESOLVE_PROMPTS = [
    "knee", "left knee", "bad lower back", "kettlebell", "no barbell",
    "exclude deadlifts", "only dumbbells and kettlebell", "squat", "xyzzy",
    "Build a session. No barbell. Exclude deadlifts.",
    "Frobnicate the wibble. Glorp the snarf.",
]


def emit_resolve_vectors() -> None:
    graph = load_local_graph(FITGRAPH / "graph" / "exercise_kg.seed.json")
    vectors = []
    for prompt in RESOLVE_PROMPTS:
        constraints = resolve_text(prompt, graph)
        vectors.append({
            "text": prompt,
            "expected": [
                {"constraint_type": c.constraint_type, "value": c.value, "hard": c.hard,
                 "negated": c.negated, "laterality": c.laterality, "graph_paths": list(c.graph_paths),
                 "verified": c.verified, "resolution_status": c.resolution_status,
                 "safety_behavior": c.safety_behavior,
                 "confidence": c.confidence, "resolution_method": c.resolution_method}
                for c in constraints
            ],
        })
    RESOLVE_VECTORS.parent.mkdir(parents=True, exist_ok=True)
    RESOLVE_VECTORS.write_text(json.dumps({"vectors": vectors}, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {RESOLVE_VECTORS.relative_to(REPO)}: {len(vectors)} resolve vectors")


from kg.alternatives import select_alternatives  # noqa: E402

ALT_VECTORS = REPO / "Tests/KGKitTests/Fixtures/conformance/alternatives_vectors.json"


def emit_alternatives_vectors() -> None:
    graph = load_local_graph(FITGRAPH / "graph" / "exercise_kg.seed.json")
    rules = load_safety_rules(FITGRAPH / "graph")
    jordan_equipment = ["Dumbbell", "Kettlebell", "Yoga Mat"]
    constraints = (_c(constraint_type="BodyRegion", value="left_knee", hard=True, source_text="left knee"),)
    receipts = evaluate_candidates(available_equipment=jordan_equipment,
                                   constraints=constraints, graph=graph, safety_rules=rules)
    alts = select_alternatives(receipts, available_equipment=jordan_equipment, graph=graph)
    vector = {
        "available_equipment": jordan_equipment,
        "constraints": [{"constraint_type": c.constraint_type, "value": c.value, "hard": c.hard,
                         "source_text": c.source_text, "negated": c.negated} for c in constraints],
        "expected_alternatives": [
            {"filtered_exercise_id": a.filtered_exercise_id,
             "alternative_exercise_id": a.alternative_exercise_id, "derived_from": a.derived_from,
             "score": a.score, "score_components": a.score_components, "graph_paths": list(a.graph_paths)}
            for a in alts
        ],
    }
    ALT_VECTORS.parent.mkdir(parents=True, exist_ok=True)
    ALT_VECTORS.write_text(json.dumps({"vectors": [vector]}, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {ALT_VECTORS.relative_to(REPO)}: {len(vector['expected_alternatives'])} alternatives")


from kg.workout_generator import generate_workout, _active_injury_constraints  # noqa: E402
from kg.graph_store import load_member_graph  # noqa: E402

WORKOUT_VECTORS = REPO / "Tests/KGKitTests/Fixtures/conformance/workout_vectors.json"

WORKOUT_SCENARIOS = [
    {"prompt": "lower body, knee-safe", "minutes": 50},
    {"prompt": "full body strength", "minutes": 50},
    {"prompt": "chest and pecs", "minutes": 40},
]


def emit_workout_vectors() -> None:
    graph = load_local_graph(FITGRAPH / "graph" / "exercise_kg.seed.json")
    member_graph = load_member_graph(FITGRAPH / "graph" / "member_kg.seed.json")
    member_id = "Member:jordan"
    member_constraints = _active_injury_constraints(member_id, member_graph, graph)
    vectors = []
    for sc in WORKOUT_SCENARIOS:
        out = generate_workout(member_id=member_id, prompt=sc["prompt"], minutes=sc["minutes"],
                               graph=graph, member_graph=member_graph)
        vectors.append({
            "prompt": sc["prompt"], "minutes": sc["minutes"],
            "available_equipment": out["available_equipment"],
            "member_constraints": [
                {"constraint_type": c.constraint_type, "value": c.value, "hard": c.hard,
                 "negated": c.negated, "laterality": c.laterality, "graph_paths": list(c.graph_paths),
                 "source_text": c.source_text, "safety_behavior": c.safety_behavior,
                 "resolution_status": c.resolution_status,
                 "confidence": c.confidence, "resolution_method": c.resolution_method} for c in member_constraints
            ],
            "expected": {
                "warmup": out["workout"]["warmup"], "main": out["workout"]["main"],
                "cooldown": out["workout"]["cooldown"],
                "selected_ids": [r["exercise_id"] for r in out["selected_exercises"]],
                "filtered_ids": [r["exercise_id"] for r in out["filtered_exercises"]],
                "alternatives": [{"filtered_exercise_id": a["filtered_exercise_id"],
                                  "alternative_exercise_id": a["alternative_exercise_id"],
                                  "score": a["score"]} for a in out["alternatives"]],
            },
        })
    WORKOUT_VECTORS.parent.mkdir(parents=True, exist_ok=True)
    WORKOUT_VECTORS.write_text(json.dumps({"vectors": vectors}, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {WORKOUT_VECTORS.relative_to(REPO)}: {len(vectors)} workout vectors")


if __name__ == "__main__":
    freeze_artifact()
    freeze_assessment_artifact()
    emit_vectors()
    emit_resolve_vectors()
    emit_alternatives_vectors()
    emit_workout_vectors()
