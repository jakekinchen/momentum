"""Deterministic member-context retrieval for Coach Copilot fact cards."""

from __future__ import annotations

from dataclasses import dataclass

from kg.graph_store import LocalGraph, load_member_graph


@dataclass(frozen=True)
class FactCard:
    """Deterministic graph-backed fact card for later Copilot prose."""

    claim: str
    confidence: str
    source_nodes: tuple[str, ...]
    query: str


def _graph(graph: LocalGraph | None) -> LocalGraph:
    return graph if graph is not None else load_member_graph()


def _member_exists(graph: LocalGraph, member_id: str) -> bool:
    try:
        graph.node(member_id)
    except KeyError:
        return False
    return True


def _missing_card(member_id: str, query: str) -> FactCard:
    return FactCard(
        claim=f"The graph has no supporting fact for {member_id}.",
        confidence="deterministic",
        source_nodes=(),
        query=query,
    )


def _source_nodes(graph: LocalGraph, node_id: str) -> tuple[str, ...]:
    return tuple(edge.target for edge in graph.outgoing(node_id, "DERIVED_FROM"))


def available_equipment(member_id: str, graph: LocalGraph | None = None) -> list[FactCard]:
    """Return deterministic fact cards for member equipment availability."""

    member_graph = _graph(graph)
    query = "member_retrieval.available_equipment"
    if not _member_exists(member_graph, member_id):
        return [_missing_card(member_id, query)]

    cards: list[FactCard] = []
    for edge in member_graph.outgoing(member_id, "HAS_EQUIPMENT_AVAILABILITY"):
        node = member_graph.node(edge.target)
        equipment_ids = tuple(str(value) for value in (node.properties or {}).get("equipment_ids", []))
        labels = tuple(item.split(":", 1)[1].replace("_", " ") for item in equipment_ids)
        cards.append(
            FactCard(
                claim=f"{member_graph.node(member_id).label} has available equipment: {', '.join(labels)}.",
                confidence="deterministic",
                source_nodes=(edge.target, *_source_nodes(member_graph, edge.target)),
                query=query,
            )
        )
    return cards or [_missing_card(member_id, query)]


def active_injuries(member_id: str, graph: LocalGraph | None = None) -> list[FactCard]:
    """Return deterministic fact cards for active injury episodes."""

    member_graph = _graph(graph)
    query = "member_retrieval.active_injuries"
    if not _member_exists(member_graph, member_id):
        return [_missing_card(member_id, query)]

    cards: list[FactCard] = []
    for edge in member_graph.outgoing(member_id, "HAS_INJURY"):
        node = member_graph.node(edge.target)
        properties = node.properties or {}
        if properties.get("status") != "active":
            continue
        region = str(properties.get("region_id", "unknown")).split(":", 1)[-1].replace("_", " ")
        started_at = str(properties.get("started_at", "unknown start date"))
        cards.append(
            FactCard(
                claim=f"{member_graph.node(member_id).label} has an active {region} injury episode since {started_at}.",
                confidence="deterministic",
                source_nodes=(edge.target, *_source_nodes(member_graph, edge.target)),
                query=query,
            )
        )
    return cards or [_missing_card(member_id, query)]


def goals(member_id: str, graph: LocalGraph | None = None) -> list[FactCard]:
    """Return deterministic fact cards for active goals."""

    member_graph = _graph(graph)
    query = "member_retrieval.goals"
    if not _member_exists(member_graph, member_id):
        return [_missing_card(member_id, query)]

    cards: list[FactCard] = []
    for edge in member_graph.outgoing(member_id, "HAS_GOAL"):
        node = member_graph.node(edge.target)
        if (node.properties or {}).get("status") != "active":
            continue
        cards.append(
            FactCard(
                claim=f"{member_graph.node(member_id).label}'s active goal is: {node.label}.",
                confidence="deterministic",
                source_nodes=(edge.target, *_source_nodes(member_graph, edge.target)),
                query=query,
            )
        )
    return cards or [_missing_card(member_id, query)]


def adherence_trend(member_id: str, graph: LocalGraph | None = None) -> list[FactCard]:
    """Return deterministic fact cards comparing adherence observations."""

    member_graph = _graph(graph)
    query = "member_retrieval.adherence_trend"
    if not _member_exists(member_graph, member_id):
        return [_missing_card(member_id, query)]

    observations = []
    for edge in member_graph.outgoing(member_id, "HAS_ADHERENCE_OBSERVATION"):
        node = member_graph.node(edge.target)
        properties = node.properties or {}
        planned = int(properties.get("planned_sessions", 0))
        completed = int(properties.get("completed_sessions", 0))
        rate = completed / planned if planned else 0.0
        observations.append((str(properties.get("week_start", "")), edge.target, completed, planned, rate))

    observations.sort(key=lambda item: item[0])
    if len(observations) < 2:
        return [_missing_card(member_id, query)]

    first = observations[0]
    latest = observations[-1]
    first_pct = round(first[4] * 100)
    latest_pct = round(latest[4] * 100)
    verb = "declined" if latest_pct < first_pct else "improved" if latest_pct > first_pct else "stayed flat"
    return [
        FactCard(
            claim=(
                f"Adherence {verb} from {first_pct}% ({first[2]}/{first[3]}) "
                f"on {first[0]} to {latest_pct}% ({latest[2]}/{latest[3]}) on {latest[0]}."
            ),
            confidence="deterministic",
            source_nodes=(first[1], latest[1]),
            query=query,
        )
    ]
