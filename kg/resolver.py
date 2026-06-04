"""Resolver boundary.

M0 intentionally does not implement resolver behavior. Later slices may parse
text into typed constraints, but eligibility and safety must remain graph-driven.
"""

from __future__ import annotations

from kg.constraints import ResolvedConstraint


def resolve_text(text: str) -> list[ResolvedConstraint]:
    """Return typed constraints from text once resolver slices are implemented."""

    raise NotImplementedError("Resolver behavior is PRD-pending after M0.")
