"""PROV-shaped receipt helpers for future decision records."""

from __future__ import annotations

from datetime import datetime, timezone


def utc_timestamp() -> str:
    """Return a stable ISO-8601 UTC timestamp for provenance records."""

    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()
