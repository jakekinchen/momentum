"""Safety decision boundary for deterministic graph traversal."""

from __future__ import annotations

from dataclasses import dataclass, field


SEVERITY_LATTICE: tuple[str, ...] = (
    "MEDICAL_HARD_BLOCK",
    "EQUIPMENT_HARD_BLOCK",
    "PROMPT_EXCLUSION",
    "MEMBER_STRONG_DISLIKE",
    "SOFT_PENALTY",
    "BOOST",
)


@dataclass(frozen=True)
class DecisionReceipt:
    """Receipt shell for future selected, filtered, downranked, and unresolved decisions."""

    decision: str
    primary_severity: str
    reason_codes: tuple[str, ...]
    primary_reason_code: str
    graph_paths: tuple[str, ...] = field(default_factory=tuple)
    constraint_fingerprint: str = ""
    graph_version: str = ""
    ruleset_version: str = ""
    ontology_lock_version: str = ""


def primary_severity(reasons: list[str]) -> str | None:
    """Choose the most severe reason by the PRD lattice."""

    for severity in SEVERITY_LATTICE:
        if severity in reasons:
            return severity
    return None
