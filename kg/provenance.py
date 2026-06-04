"""PROV-shaped receipt helpers for decision records."""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import asdict, is_dataclass
from datetime import datetime, timezone
import hashlib
import json
from typing import Any


PROV_RECEIPT_REQUIRED_FIELDS: tuple[str, ...] = (
    "exercise_id",
    "decision",
    "primary_severity",
    "reason_codes",
    "primary_reason_code",
    "graph_paths",
    "constraint_fingerprint",
    "graph_version",
    "ruleset_version",
    "ontology_lock_version",
)


def utc_timestamp() -> str:
    """Return a stable ISO-8601 UTC timestamp for provenance records."""

    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def stable_fingerprint(payload: dict[str, Any]) -> str:
    """Return a short deterministic fingerprint for receipt constraints."""

    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()[:16]


def _receipt_payload(receipt: Any) -> dict[str, Any]:
    if isinstance(receipt, Mapping):
        return dict(receipt)
    if is_dataclass(receipt) and not isinstance(receipt, type):
        return asdict(receipt)
    return {
        field: getattr(receipt, field)
        for field in PROV_RECEIPT_REQUIRED_FIELDS
        if hasattr(receipt, field)
    }


def _has_text(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def validate_decision_receipt(receipt: Any) -> list[str]:
    """Validate the minimal PROV-shaped fields required on a decision receipt."""

    payload = _receipt_payload(receipt)
    errors: list[str] = []

    for field in PROV_RECEIPT_REQUIRED_FIELDS:
        if field not in payload:
            errors.append(f"DecisionReceipt missing required field: {field}")

    for field in (
        "exercise_id",
        "decision",
        "primary_severity",
        "primary_reason_code",
        "constraint_fingerprint",
        "graph_version",
        "ruleset_version",
        "ontology_lock_version",
    ):
        if field in payload and not _has_text(payload[field]):
            errors.append(f"DecisionReceipt.{field} must be a non-empty string")

    reason_codes = payload.get("reason_codes")
    if "reason_codes" in payload:
        if not isinstance(reason_codes, (tuple, list)) or not reason_codes:
            errors.append("DecisionReceipt.reason_codes must be a non-empty sequence")
        elif not all(_has_text(reason_code) for reason_code in reason_codes):
            errors.append("DecisionReceipt.reason_codes must contain non-empty strings")

    graph_paths = payload.get("graph_paths")
    if "graph_paths" in payload:
        if not isinstance(graph_paths, (tuple, list)):
            errors.append("DecisionReceipt.graph_paths must be a sequence")
        elif not all(isinstance(path, str) for path in graph_paths):
            errors.append("DecisionReceipt.graph_paths must contain strings")

    return errors
