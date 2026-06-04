"""Member-context retrieval boundary for Coach Copilot fact cards."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class FactCard:
    """Deterministic graph-backed fact card for later Copilot prose."""

    claim: str
    confidence: str
    source_nodes: tuple[str, ...]
    query: str
