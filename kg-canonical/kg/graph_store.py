"""Local graph artifact inspection and tiny graph traversal helpers."""

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


@dataclass(frozen=True)
class GraphNode:
    """A typed local graph node loaded from a seed artifact."""

    id: str
    type: str
    label: str
    aliases: tuple[str, ...] = ()
    properties: dict[str, Any] | None = None


@dataclass(frozen=True)
class GraphEdge:
    """A typed local graph edge loaded from a seed artifact."""

    source: str
    predicate: str
    target: str
    properties: dict[str, Any] | None = None

    def path(self) -> str:
        return f"{self.source} -{self.predicate}-> {self.target}"


@dataclass(frozen=True)
class LocalGraph:
    """Small closed-world graph snapshot for deterministic local traversal."""

    nodes: dict[str, GraphNode]
    edges: tuple[GraphEdge, ...]

    def node(self, node_id: str) -> GraphNode:
        try:
            return self.nodes[node_id]
        except KeyError as exc:
            raise KeyError(f"Unknown graph node: {node_id}") from exc

    def outgoing(self, node_id: str, predicate: str | None = None) -> tuple[GraphEdge, ...]:
        return tuple(
            edge
            for edge in self.edges
            if edge.source == node_id and (predicate is None or edge.predicate == predicate)
        )

    def incoming(self, node_id: str, predicate: str | None = None) -> tuple[GraphEdge, ...]:
        return tuple(
            edge
            for edge in self.edges
            if edge.target == node_id and (predicate is None or edge.predicate == predicate)
        )

    def nodes_by_type(self, node_type: str) -> tuple[GraphNode, ...]:
        return tuple(node for node in self.nodes.values() if node.type == node_type)

    def descendants_by_incoming_part_of(self, root_id: str) -> tuple[GraphNode, ...]:
        """Return root plus nodes that recursively point to root through PART_OF."""

        self.node(root_id)
        seen = {root_id}
        ordered = [root_id]
        stack = [root_id]
        while stack:
            current = stack.pop()
            for edge in self.incoming(current, "PART_OF"):
                if edge.source not in seen:
                    seen.add(edge.source)
                    ordered.append(edge.source)
                    stack.append(edge.source)
        return tuple(self.nodes[node_id] for node_id in ordered)

    def part_of_closure_paths(self, root_id: str) -> tuple[str, ...]:
        """Return deterministic graph paths proving PART_OF descendants of root."""

        self.node(root_id)
        paths: list[str] = []
        seen = {root_id}
        stack = [root_id]
        while stack:
            current = stack.pop()
            for edge in sorted(self.incoming(current, "PART_OF"), key=lambda item: item.source):
                if edge.source not in seen:
                    seen.add(edge.source)
                    paths.append(edge.path())
                    stack.append(edge.source)
        return tuple(paths)

    def part_of_path(self, source_id: str, target_id: str) -> tuple[str, ...]:
        """Return one deterministic PART_OF path from source to target, if present."""

        self.node(source_id)
        self.node(target_id)
        if source_id == target_id:
            return ()

        queue: list[tuple[str, tuple[str, ...]]] = [(source_id, ())]
        seen = {source_id}
        while queue:
            current, path = queue.pop(0)
            for edge in sorted(self.outgoing(current, "PART_OF"), key=lambda item: item.target):
                next_path = (*path, edge.path())
                if edge.target == target_id:
                    return next_path
                if edge.target not in seen:
                    seen.add(edge.target)
                    queue.append((edge.target, next_path))
        return ()


def load_json(path: Path) -> dict[str, Any]:
    """Load one JSON object from disk."""

    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"{path.name} must contain a JSON object")
    return payload


def _node_from_payload(payload: dict[str, Any]) -> GraphNode:
    aliases = payload.get("aliases", [])
    if not isinstance(aliases, list):
        raise ValueError(f"{payload.get('id', '<unknown>')} aliases must be a list")
    return GraphNode(
        id=str(payload["id"]),
        type=str(payload["type"]),
        label=str(payload["label"]),
        aliases=tuple(str(alias) for alias in aliases),
        properties=payload.get("properties", {}),
    )


def _edge_from_payload(payload: dict[str, Any]) -> GraphEdge:
    return GraphEdge(
        source=str(payload["source"]),
        predicate=str(payload["predicate"]),
        target=str(payload["target"]),
        properties=payload.get("properties", {}),
    )


def load_local_graph(path: Path = GRAPH_DIR / "exercise_kg.seed.json") -> LocalGraph:
    """Load the local runtime graph seed as a typed closed-world snapshot."""

    payload = load_json(path)
    raw_nodes = payload.get("nodes", [])
    raw_edges = payload.get("edges", [])
    if not isinstance(raw_nodes, list) or not isinstance(raw_edges, list):
        raise ValueError(f"{path.name} must contain list-valued nodes and edges")

    graph_nodes = [_node_from_payload(node) for node in raw_nodes]
    nodes = {node.id: node for node in graph_nodes}
    if len(nodes) != len(graph_nodes):
        raise ValueError(f"{path.name} contains duplicate node IDs")
    edges = tuple(_edge_from_payload(edge) for edge in raw_edges)
    for edge in edges:
        if edge.source not in nodes:
            raise ValueError(f"{path.name} edge source is missing: {edge.source}")
        if edge.target not in nodes:
            raise ValueError(f"{path.name} edge target is missing: {edge.target}")
    return LocalGraph(nodes=nodes, edges=edges)


def load_member_graph(path: Path = GRAPH_DIR / "member_kg.seed.json") -> LocalGraph:
    """Load the local member-context graph seed as a typed closed-world snapshot."""

    return load_local_graph(path)


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
