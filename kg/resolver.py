"""Deterministic local resolver for the M1 seed graph slice."""

from __future__ import annotations

import re

from kg.constraints import ResolvedConstraint
from kg.graph_store import GraphNode, LocalGraph, load_local_graph

_BOUNDARY_PUNCTUATION = ".,;:!?\"'()[]{}"


def _normalize(text: str) -> str:
    normalized = re.sub(r"\s+", " ", text.strip().lower())
    return normalized.strip(_BOUNDARY_PUNCTUATION)


def _node_value(node_id: str) -> str:
    return node_id.split(":", 1)[1]


def _exact_label_or_alias_match(normalized: str, graph: LocalGraph) -> GraphNode | None:
    """Find a deterministic local graph concept match by label or alias."""

    for node in sorted(graph.nodes.values(), key=lambda item: item.id):
        terms = {_normalize(node.label), *(_normalize(alias) for alias in node.aliases)}
        if normalized in terms:
            return node
    return None


def _resolved_node(
    *,
    graph: LocalGraph,
    source_text: str,
    constraint_type: str,
    node_id: str,
    hard: bool = False,
    negated: bool = False,
    laterality: str | None = None,
    safety_behavior: str | None = None,
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
        safety_behavior=safety_behavior,
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


def _allowed_equipment_subset(
    *,
    graph: LocalGraph,
    source_text: str,
    normalized: str,
) -> list[ResolvedConstraint] | None:
    if not normalized.startswith("only "):
        return None

    equipment_text = normalized.removeprefix("only ").strip()
    terms = [term.strip() for term in re.split(r"\s*(?:,| and )\s*", equipment_text)]
    terms = [term for term in terms if term]
    if not terms:
        return None

    constraints: list[ResolvedConstraint] = []
    seen: set[str] = set()
    for term in terms:
        matched_node = _exact_label_or_alias_match(term, graph)
        if matched_node is None or matched_node.type != "Equipment":
            return None
        if matched_node.id in seen:
            continue
        seen.add(matched_node.id)
        constraints.append(
            _resolved_node(
                graph=graph,
                source_text=source_text,
                constraint_type="Equipment",
                node_id=matched_node.id,
                hard=True,
                safety_behavior="allowed_equipment_only",
            )
        )
    return constraints


def resolve_text(text: str, graph: LocalGraph | None = None) -> list[ResolvedConstraint]:
    """Return typed constraints from local seed facts, never prose decisions."""

    local_graph = graph if graph is not None else load_local_graph()
    normalized = _normalize(text)

    if allowed_equipment := _allowed_equipment_subset(
        graph=local_graph,
        source_text=text,
        normalized=normalized,
    ):
        return allowed_equipment

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

    if matched_node := _exact_label_or_alias_match(normalized, local_graph):
        return [
            _resolved_node(
                graph=local_graph,
                source_text=text,
                constraint_type=matched_node.type,
                node_id=matched_node.id,
            )
        ]

    return [_unresolved(text, normalized)]
