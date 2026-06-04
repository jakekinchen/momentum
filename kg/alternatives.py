"""Alternative selection from already-safe exercise receipts."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

from kg.graph_store import LocalGraph, load_local_graph
from kg.safety import DecisionReceipt


@dataclass(frozen=True)
class AlternativeRecord:
    """Deterministic alternative for one filtered exercise."""

    filtered_exercise_id: str
    alternative_exercise_id: str
    derived_from: str
    score: float
    score_components: dict[str, float]
    graph_paths: tuple[str, ...]


@dataclass(frozen=True)
class WorkoutCandidateResult:
    """Small workout-candidate contract built from one safety result set."""

    selected_receipts: tuple[DecisionReceipt, ...]
    filtered_receipts: tuple[DecisionReceipt, ...]
    alternatives: tuple[AlternativeRecord, ...]


def _node_id(prefix: str, value: str) -> str:
    if value.startswith(f"{prefix}:"):
        return value
    return f"{prefix}:{value.strip().lower().replace(' ', '_')}"


def _equipment_ids(available_equipment: Iterable[str]) -> frozenset[str]:
    return frozenset(_node_id("Equipment", value) for value in available_equipment)


def _targets(graph: LocalGraph, exercise_id: str) -> frozenset[str]:
    return frozenset(edge.target for edge in graph.outgoing(exercise_id, "TARGETS"))


def _patterns(graph: LocalGraph, exercise_id: str) -> frozenset[str]:
    return frozenset(edge.target for edge in graph.outgoing(exercise_id, "HAS_PATTERN"))


def _requires(graph: LocalGraph, exercise_id: str) -> frozenset[str]:
    return frozenset(edge.target for edge in graph.outgoing(exercise_id, "REQUIRES"))


def _priority_score(graph: LocalGraph, exercise_id: str) -> float:
    value = (graph.node(exercise_id).properties or {}).get("priority_score", 0.0)
    return float(value)


def _target_overlap(graph: LocalGraph, filtered_id: str, alternative_id: str) -> float:
    filtered_targets = _targets(graph, filtered_id)
    alternative_targets = _targets(graph, alternative_id)
    if not filtered_targets or not alternative_targets:
        return 0.0
    return len(filtered_targets & alternative_targets) / len(filtered_targets | alternative_targets)


def _pattern_similarity(graph: LocalGraph, filtered_id: str, alternative_id: str) -> float:
    filtered_patterns = _patterns(graph, filtered_id)
    alternative_patterns = _patterns(graph, alternative_id)
    if not filtered_patterns or not alternative_patterns:
        return 0.0
    return 1.0 if filtered_patterns & alternative_patterns else 0.0


def _equipment_preference(
    graph: LocalGraph,
    alternative_id: str,
    available_equipment: frozenset[str],
) -> float:
    required = _requires(graph, alternative_id)
    if not required:
        return 1.0
    return 1.0 if required <= available_equipment else 0.0


def _score_components(
    graph: LocalGraph,
    filtered_id: str,
    alternative_id: str,
    available_equipment: frozenset[str],
) -> dict[str, float]:
    return {
        "target_overlap": _target_overlap(graph, filtered_id, alternative_id),
        "movement_pattern_similarity": _pattern_similarity(graph, filtered_id, alternative_id),
        "equipment_preference": _equipment_preference(graph, alternative_id, available_equipment),
        "priority_tier": _priority_score(graph, alternative_id),
    }


def _weighted_score(components: dict[str, float]) -> float:
    return round(
        (0.45 * components["target_overlap"])
        + (0.35 * components["movement_pattern_similarity"])
        + (0.10 * components["equipment_preference"])
        + (0.10 * components["priority_tier"]),
        6,
    )


def _alternative_paths(graph: LocalGraph, filtered_id: str, alternative_id: str) -> tuple[str, ...]:
    paths: list[str] = []
    shared_targets = _targets(graph, filtered_id) & _targets(graph, alternative_id)
    shared_patterns = _patterns(graph, filtered_id) & _patterns(graph, alternative_id)

    for edge in graph.outgoing(filtered_id, "TARGETS"):
        if edge.target in shared_targets:
            paths.append(edge.path())
    for edge in graph.outgoing(alternative_id, "TARGETS"):
        if edge.target in shared_targets:
            paths.append(edge.path())
    for edge in graph.outgoing(filtered_id, "HAS_PATTERN"):
        if edge.target in shared_patterns:
            paths.append(edge.path())
    for edge in graph.outgoing(alternative_id, "HAS_PATTERN"):
        if edge.target in shared_patterns:
            paths.append(edge.path())
    for predicate in ("REQUIRES", "STRESSES"):
        paths.extend(edge.path() for edge in graph.outgoing(alternative_id, predicate))
    return tuple(paths)


def select_alternatives(
    receipts: Iterable[DecisionReceipt],
    *,
    available_equipment: Iterable[str],
    graph: LocalGraph | None = None,
) -> list[AlternativeRecord]:
    """Select alternatives only from receipts already marked selected."""

    local_graph = graph if graph is not None else load_local_graph()
    receipt_list = tuple(receipts)
    safe_receipts = {
        receipt.exercise_id: receipt
        for receipt in receipt_list
        if receipt.decision == "selected"
    }
    if not safe_receipts:
        return []

    available = _equipment_ids(available_equipment)
    alternatives: list[AlternativeRecord] = []
    filtered_receipts = sorted(
        (receipt for receipt in receipt_list if receipt.decision == "filtered"),
        key=lambda receipt: receipt.exercise_id,
    )
    for filtered_receipt in filtered_receipts:
        scored: list[AlternativeRecord] = []
        for alternative_id in sorted(safe_receipts):
            components = _score_components(
                local_graph,
                filtered_receipt.exercise_id,
                alternative_id,
                available,
            )
            scored.append(
                AlternativeRecord(
                    filtered_exercise_id=filtered_receipt.exercise_id,
                    alternative_exercise_id=alternative_id,
                    derived_from=filtered_receipt.exercise_id,
                    score=_weighted_score(components),
                    score_components=components,
                    graph_paths=_alternative_paths(
                        local_graph,
                        filtered_receipt.exercise_id,
                        alternative_id,
                    ),
                )
            )
        scored.sort(key=lambda record: (-record.score, record.alternative_exercise_id))
        alternatives.append(scored[0])
    return alternatives


def build_workout_candidates(
    receipts: Iterable[DecisionReceipt],
    *,
    available_equipment: Iterable[str],
    graph: LocalGraph | None = None,
) -> WorkoutCandidateResult:
    """Build selected, filtered, and alternative records from one safety run."""

    receipt_list = tuple(receipts)
    selected = tuple(receipt for receipt in receipt_list if receipt.decision == "selected")
    filtered = tuple(receipt for receipt in receipt_list if receipt.decision == "filtered")
    alternatives = tuple(
        select_alternatives(
            receipt_list,
            available_equipment=available_equipment,
            graph=graph,
        )
    )
    return WorkoutCandidateResult(
        selected_receipts=selected,
        filtered_receipts=filtered,
        alternatives=alternatives,
    )
