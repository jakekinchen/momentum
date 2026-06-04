"""PROV-shaped receipt helpers for future decision records."""

from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
from typing import Any


def utc_timestamp() -> str:
    """Return a stable ISO-8601 UTC timestamp for provenance records."""

    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def stable_fingerprint(payload: dict[str, Any]) -> str:
    """Return a short deterministic fingerprint for receipt constraints."""

    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()[:16]
