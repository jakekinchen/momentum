"""Command contract for graph-driven workout generation demos."""

from __future__ import annotations

from dataclasses import asdict
import argparse
import json
from pathlib import Path
import re
from typing import Any

from kg.alternatives import AlternativeRecord, build_workout_candidates
from kg.assessment_import import write_assessment_import_artifacts
from kg.constraints import ResolvedConstraint
from kg.graph_store import LocalGraph, load_local_graph, load_member_graph
from kg.resolver import resolve_text
from kg.safety import DecisionReceipt, evaluate_candidates


LOWER_BODY_TARGETS = frozenset(
    {
        "MuscleGroup:glutes",
        "MuscleGroup:quads",
        "MuscleGroup:hamstrings",
        "MuscleGroup:calves",
        "MuscleGroup:hip_flexors",
        "MuscleGroup:hip_adductors",
        "MuscleGroup:lower_back",
    }
)

QUARANTINED_EXERCISE_IDS = frozenset(
    {
        "Exercise:jumping_jack",
    }
)


def _node_value(node_id: str) -> str:
    return node_id.split(":", 1)[1]


def _equipment_from_member(member_id: str, member_graph: LocalGraph) -> set[str]:
    equipment: set[str] = set()
    for edge in member_graph.outgoing(member_id, "HAS_EQUIPMENT_AVAILABILITY"):
        node = member_graph.node(edge.target)
        equipment.update(str(item) for item in (node.properties or {}).get("equipment_ids", []))
    return equipment


def _equipment_from_allowed_constraints(constraints: list[ResolvedConstraint]) -> set[str]:
    return {
        f"Equipment:{constraint.value}"
        for constraint in constraints
        if constraint.constraint_type == "Equipment"
        and constraint.hard
        and constraint.safety_behavior == "allowed_equipment_only"
    }


def _active_injury_constraints(member_id: str, member_graph: LocalGraph, graph: LocalGraph) -> list[ResolvedConstraint]:
    constraints: list[ResolvedConstraint] = []
    for edge in member_graph.outgoing(member_id, "HAS_INJURY"):
        node = member_graph.node(edge.target)
        properties = node.properties or {}
        if properties.get("status") != "active":
            continue
        region_id = str(properties.get("region_id", ""))
        if not region_id:
            continue
        try:
            graph.node(region_id)
        except KeyError:
            continue
        constraints.append(
            ResolvedConstraint(
                constraint_type="BodyRegion",
                value=_node_value(region_id),
                hard=True,
                source_text=f"{node.label} active injury",
                graph_paths=graph.part_of_closure_paths(region_id),
                laterality=(graph.node(region_id).properties or {}).get("laterality"),
                safety_behavior="block_if_safety_critical",
            )
        )
    return constraints


def _is_lower_body_candidate(graph: LocalGraph, exercise_id: str) -> bool:
    targets = {edge.target for edge in graph.outgoing(exercise_id, "TARGETS")}
    patterns = {graph.node(edge.target).label.lower() for edge in graph.outgoing(exercise_id, "HAS_PATTERN")}
    return bool(targets & LOWER_BODY_TARGETS) or any("lower" in pattern for pattern in patterns)


def _normalized_phrase(text: str) -> str:
    return " ".join(re.sub(r"[^a-z0-9]+", " ", text.lower()).split())


def _contains_phrase(haystack: str, needle: str) -> bool:
    return bool(needle) and f" {needle} " in f" {haystack} "


def _exercise_search_terms(graph: LocalGraph, exercise_id: str) -> tuple[str, ...]:
    node = graph.node(exercise_id)
    terms = [
        node.label,
        *node.aliases,
        node.id,
        _node_value(node.id).replace("_", " "),
    ]
    return tuple(term for term in (_normalized_phrase(term) for term in terms) if term)


def _exact_exercise_candidate_ids(prompt: str, graph: LocalGraph, exercise_ids: list[str]) -> list[str]:
    normalized_prompt = _normalized_phrase(prompt)
    return [
        exercise_id
        for exercise_id in exercise_ids
        if any(_contains_phrase(normalized_prompt, term) for term in _exercise_search_terms(graph, exercise_id))
    ]


def _candidate_ids(prompt: str, graph: LocalGraph) -> list[str]:
    all_exercise_ids = sorted(node.id for node in graph.nodes_by_type("Exercise"))
    exercise_ids = [
        exercise_id
        for exercise_id in all_exercise_ids
        if exercise_id not in QUARANTINED_EXERCISE_IDS
    ]
    normalized = prompt.lower()
    exact_matches_including_quarantine = _exact_exercise_candidate_ids(prompt, graph, all_exercise_ids)
    exact_matches = [
        exercise_id
        for exercise_id in exact_matches_including_quarantine
        if exercise_id not in QUARANTINED_EXERCISE_IDS
    ]
    if exact_matches_including_quarantine:
        return exact_matches
    if "lower" in normalized or "leg" in normalized or "knee" in normalized:
        return [exercise_id for exercise_id in exercise_ids if _is_lower_body_candidate(graph, exercise_id)]
    if "preacher" in normalized:
        return [exercise_id for exercise_id in exercise_ids if "preacher" in graph.node(exercise_id).label.lower()]
    if (
        re.search(r"\b(rows?|rowing)\b", normalized)
        or re.search(r"\bupper[- ]back\b", normalized)
        or re.search(r"\b(lats?|latissimus)\b", normalized)
    ):
        return [
            exercise_id
            for exercise_id in exercise_ids
            if any(edge.target == "ExerciseFamily:row_family" for edge in graph.outgoing(exercise_id, "VARIANT_OF"))
            or any(
                edge.target in {"MuscleGroup:upper_back", "MuscleGroup:lats"}
                for edge in graph.outgoing(exercise_id, "TARGETS")
            )
        ]
    if "pec" in normalized or "chest" in normalized:
        return [
            exercise_id
            for exercise_id in exercise_ids
            if any(edge.target == "MuscleGroup:chest" for edge in graph.outgoing(exercise_id, "TARGETS"))
        ]
    return exercise_ids


def _prescription(graph: LocalGraph, exercise_id: str, section: str) -> dict[str, Any]:
    node = graph.node(exercise_id)
    properties = node.properties or {}
    if properties.get("is_duration") and not properties.get("is_reps"):
        prescription = {"duration_seconds": 40 if section == "warmup" else 60, "rest_seconds": 30}
    else:
        prescription = {
            "sets": 2 if section in {"warmup", "cooldown"} else 3,
            "reps": "8-10" if properties.get("supports_weight") else "10-12",
            "rest_seconds": 45 if section in {"warmup", "cooldown"} else 75,
        }
    return {"exercise_id": exercise_id, "name": node.label, **prescription}


def _workout_sections(graph: LocalGraph, selected: tuple[DecisionReceipt, ...]) -> dict[str, list[dict[str, Any]]]:
    selected_ids = [receipt.exercise_id for receipt in selected]
    mobility = [
        exercise_id
        for exercise_id in selected_ids
        if any(
            "mobility" in graph.node(edge.target).label.lower()
            or "regen" in graph.node(edge.target).label.lower()
            or "yoga" in graph.node(edge.target).label.lower()
            for edge in graph.outgoing(exercise_id, "HAS_PATTERN")
        )
    ]
    main = [exercise_id for exercise_id in selected_ids if exercise_id not in mobility]
    main.sort(key=lambda exercise_id: -(float((graph.node(exercise_id).properties or {}).get("priority_score", 0.0))))
    warmup_ids = mobility[:2]
    main_ids = main[:5] if main else selected_ids[:5]
    cooldown_ids = mobility[2:4]
    return {
        "warmup": [_prescription(graph, exercise_id, "warmup") for exercise_id in warmup_ids],
        "main": [_prescription(graph, exercise_id, "main") for exercise_id in main_ids],
        "cooldown": [_prescription(graph, exercise_id, "cooldown") for exercise_id in cooldown_ids],
    }


def _receipt_payload(receipt: DecisionReceipt, graph: LocalGraph) -> dict[str, Any]:
    payload = asdict(receipt)
    payload["name"] = graph.node(receipt.exercise_id).label
    return payload


def _alternative_payload(record: AlternativeRecord, graph: LocalGraph) -> dict[str, Any]:
    payload = asdict(record)
    payload["filtered_name"] = graph.node(record.filtered_exercise_id).label
    payload["alternative_name"] = graph.node(record.alternative_exercise_id).label
    return payload


def generate_workout(
    *,
    member_id: str = "Member:jordan",
    prompt: str,
    minutes: int,
    graph: LocalGraph | None = None,
    member_graph: LocalGraph | None = None,
) -> dict[str, Any]:
    """Generate a deterministic workout payload from graph receipts."""

    if graph is None or member_graph is None:
        paths = write_assessment_import_artifacts()
        graph = graph or load_local_graph(Path(paths["exercise_graph"]))
        member_graph = member_graph or load_member_graph(Path(paths["member_graph"]))

    prompt_constraints = resolve_text(prompt, graph=graph)
    constraints = [*prompt_constraints, *_active_injury_constraints(member_id, member_graph, graph)]
    allowed_equipment = _equipment_from_allowed_constraints(prompt_constraints)
    available_equipment = allowed_equipment or _equipment_from_member(member_id, member_graph)
    candidate_ids = _candidate_ids(prompt, graph)
    receipts = evaluate_candidates(
        candidate_ids,
        available_equipment=available_equipment,
        constraints=constraints,
        graph=graph,
    )
    candidate_result = build_workout_candidates(
        receipts,
        available_equipment=available_equipment,
        graph=graph,
    )
    unresolved = [
        asdict(constraint)
        for constraint in constraints
        if constraint.constraint_type == "UnresolvedConcept"
    ]
    return {
        "member_id": member_id,
        "prompt": prompt,
        "time_window_minutes": minutes,
        "available_equipment": sorted(available_equipment),
        "resolved_constraints": [asdict(constraint) for constraint in constraints],
        "unresolved_concepts": unresolved,
        "workout": _workout_sections(graph, candidate_result.selected_receipts),
        "selected_exercises": [
            _receipt_payload(receipt, graph) for receipt in candidate_result.selected_receipts
        ],
        "filtered_exercises": [
            _receipt_payload(receipt, graph) for receipt in candidate_result.filtered_receipts
        ],
        "alternatives": [
            _alternative_payload(record, graph) for record in candidate_result.alternatives
        ],
        "decision_receipts": [_receipt_payload(receipt, graph) for receipt in receipts],
        "graph_contract": {
            "eligibility_source": "deterministic_graph_traversal",
            "llm_decides_eligibility": False,
            "vector_search_enforces_safety": False,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate a graph-backed FitGraph workout.")
    parser.add_argument("--member", default="Member:jordan")
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--minutes", type=int, default=50)
    args = parser.parse_args()
    print(
        json.dumps(
            generate_workout(member_id=args.member, prompt=args.prompt, minutes=args.minutes),
            indent=2,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
