"""Typed constraint shapes shared by resolver and safety modules."""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class ResolvedConstraint:
    """A parsed constraint candidate; safety decisions remain graph-driven."""

    constraint_type: str
    value: str
    hard: bool
    source_text: str
    graph_paths: tuple[str, ...] = field(default_factory=tuple)
    verified: bool = False
