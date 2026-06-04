"""Alternative-selection boundary.

Alternatives must be selected only from an already-safe exercise pool in later
slices.
"""

from __future__ import annotations

from typing import Any


def select_alternatives(safe_pool: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Placeholder for PRD alternative scoring over an already-safe pool."""

    return list(safe_pool)
