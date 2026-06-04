"""Deterministic local resolver for the M1 seed graph slice."""

from __future__ import annotations

import re

from kg.constraints import ResolvedConstraint
from kg.graph_store import LocalGraph, load_local_graph


def _normalize(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip().lower())


def _node_value(node_id: str) -> str:
    return node_id.split(":", 1)[1]


def _resolved_node(
    *,
    graph: LocalGraph,
    source_text: str,
    constraint_type: str,
    node_id: str,
    hard: bool = False,
    negated: bool = False,
    laterality: str | None = None,
    graph_paths: tuple[str, ...] = (),
) -> ResolvedConstraint:
    graph.node(node_id)
    return ResolvedConstraint(
        constraint_type=constraint_type,
        value=_node_value(node_id),
        hard=hard,
        source_text=source_text,
        graph_paths=graph_paths,
        verified=False,
        negated=negated,
        laterality=laterality,
    )


def _unresolved(source_text: str, normalized_text: str) -> ResolvedConstraint:
    return ResolvedConstraint(
        constraint_type="UnresolvedConcept",
        value=normalized_text,
        hard=True,
        source_text=source_text,
        verified=False,
        resolution_status="needs_review",
        safety_behavior="ask_clarification",
    )


def resolve_text(text: str, graph: LocalGraph | None = None) -> list[ResolvedConstraint]:
    """Return typed constraints from local seed facts, never prose decisions."""

    local_graph = graph if graph is not None else load_local_graph()
    normalized = _normalize(text)

    if normalized == "knee":
        return [
            _resolved_node(
                graph=local_graph,
                source_text=text,
                constraint_type="BodyRegion",
                node_id="BodyRegion:knee",
                graph_paths=local_graph.part_of_closure_paths("BodyRegion:knee"),
            )
        ]

    if normalized == "left knee":
        paths = tuple(edge.path() for edge in local_graph.outgoing("BodyRegion:left_knee", "PART_OF"))
        return [
            _resolved_node(
                graph=local_graph,
                source_text=text,
                constraint_type="BodyRegion",
                node_id="BodyRegion:left_knee",
                laterality="left",
                graph_paths=paths,
            )
        ]

    if normalized == "kettlebell":
        return [
            _resolved_node(
                graph=local_graph,
                source_text=text,
                constraint_type="Equipment",
                node_id="Equipment:kettlebell",
            )
        ]

    if normalized == "no barbell":
        return [
            _resolved_node(
                graph=local_graph,
                source_text=text,
                constraint_type="Equipment",
                node_id="Equipment:barbell",
                hard=True,
                negated=True,
            )
        ]

    if normalized == "exclude deadlifts":
        return [
            _resolved_node(
                graph=local_graph,
                source_text=text,
                constraint_type="ExerciseFamily",
                node_id="ExerciseFamily:deadlift_family",
                hard=True,
                negated=True,
            )
        ]

    return [_unresolved(text, normalized)]
