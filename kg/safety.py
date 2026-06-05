"""Deterministic safety evaluation over the local FitGraph seed graph."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Iterable

from kg.constraints import ResolvedConstraint
from kg.graph_store import GRAPH_DIR, GraphEdge, LocalGraph, load_json, load_local_graph
from kg.provenance import stable_fingerprint
from kg.validation import GRAPH_VERSION, RULESET_VERSION


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
    """Receipt for selected, filtered, downranked, and unresolved decisions."""

    exercise_id: str
    decision: str
    primary_severity: str
    reason_codes: tuple[str, ...]
    primary_reason_code: str
    graph_paths: tuple[str, ...] = field(default_factory=tuple)
    constraint_fingerprint: str = ""
    graph_version: str = ""
    ruleset_version: str = ""
    ontology_lock_version: str = ""


@dataclass(frozen=True)
class SafetyRule:
    """Minimal safety rule loaded from the local rule seed."""

    id: str
    severity: str
    reason_code: str
    uses_concepts: tuple[str, ...]
    match: dict[str, Any]


@dataclass(frozen=True)
class SafetyReason:
    """One applicable safety reason before receipt primary selection."""

    severity: str
    reason_code: str
    graph_paths: tuple[str, ...] = ()


ONTOLOGY_LOCK_VERSION = "ontology-lock-m0-unverified"
HARD_BLOCK_SEVERITIES = frozenset(
    {
        "MEDICAL_HARD_BLOCK",
        "EQUIPMENT_HARD_BLOCK",
        "PROMPT_EXCLUSION",
    }
)


def primary_severity(reasons: list[str]) -> str | None:
    """Choose the most severe reason by the PRD lattice."""

    for severity in SEVERITY_LATTICE:
        if severity in reasons:
            return severity
    return None


def load_safety_rules(graph_dir=GRAPH_DIR) -> tuple[SafetyRule, ...]:
    """Load local deterministic safety rules from the seed artifact."""

    payload = load_json(graph_dir / "safety_rules.seed.json")
    rules = []
    for item in payload.get("rules", []):
        rules.append(
            SafetyRule(
                id=str(item["id"]),
                severity=str(item["severity"]),
                reason_code=str(item["reason_code"]),
                uses_concepts=tuple(str(concept) for concept in item.get("uses_concepts", [])),
                match=dict(item.get("match", {})),
            )
        )
    return tuple(rules)


def _node_id(prefix: str, value: str) -> str:
    if value.startswith(f"{prefix}:"):
        return value
    return f"{prefix}:{value.strip().lower().replace(' ', '_')}"


def _equipment_ids(available_equipment: Iterable[str]) -> frozenset[str]:
    return frozenset(_node_id("Equipment", value) for value in available_equipment)


def _constraint_node_id(constraint: ResolvedConstraint) -> str:
    return _node_id(constraint.constraint_type, constraint.value)


def _matches_properties(edge: GraphEdge, expected: dict[str, Any]) -> bool:
    properties = edge.properties or {}
    for key, expected_value in expected.items():
        actual = properties.get(key)
        if isinstance(expected_value, list):
            if actual not in expected_value:
                return False
        elif actual != expected_value:
            return False
    return True


def _restriction_applies_to_rule(
    graph: LocalGraph,
    restriction_id: str,
    rule: SafetyRule,
) -> bool:
    for rule_region_id in rule.uses_concepts:
        if restriction_id == rule_region_id:
            return True
        if graph.part_of_path(restriction_id, rule_region_id):
            return True
    return False


def _stress_hits_restriction(
    graph: LocalGraph,
    stress_target_id: str,
    restriction_id: str,
) -> tuple[str, ...] | None:
    if stress_target_id == restriction_id:
        return ()
    path = graph.part_of_path(stress_target_id, restriction_id)
    if path:
        return path
    reverse_path = graph.part_of_path(restriction_id, stress_target_id)
    if reverse_path:
        return reverse_path
    return None


def _medical_reasons(
    exercise_id: str,
    graph: LocalGraph,
    constraints: tuple[ResolvedConstraint, ...],
    rules: tuple[SafetyRule, ...],
) -> list[SafetyReason]:
    reasons: list[SafetyReason] = []
    active_restrictions = [
        _constraint_node_id(constraint)
        for constraint in constraints
        if constraint.constraint_type == "BodyRegion" and constraint.hard and not constraint.negated
    ]
    if not active_restrictions:
        return reasons

    for stress_edge in graph.outgoing(exercise_id, "STRESSES"):
        for restriction_id in active_restrictions:
            restriction_path = _stress_hits_restriction(graph, stress_edge.target, restriction_id)
            if restriction_path is None:
                continue
            for rule in rules:
                if rule.severity != "MEDICAL_HARD_BLOCK":
                    continue
                if not _restriction_applies_to_rule(graph, restriction_id, rule):
                    continue
                if rule.match.get("edge_predicate") != "STRESSES":
                    continue
                if not _matches_properties(stress_edge, dict(rule.match.get("properties", {}))):
                    continue

                rule_paths = tuple(
                    f"{rule.id} -USES_CONCEPT-> {concept}" for concept in rule.uses_concepts
                )
                reasons.append(
                    SafetyReason(
                        severity=rule.severity,
                        reason_code=rule.reason_code,
                        graph_paths=(stress_edge.path(), *restriction_path, *rule_paths),
                    )
                )
    return reasons


def _equipment_reasons(
    exercise_id: str,
    graph: LocalGraph,
    available_equipment: frozenset[str],
    constraints: tuple[ResolvedConstraint, ...],
) -> list[SafetyReason]:
    reasons: list[SafetyReason] = []
    disallowed_equipment = {
        _constraint_node_id(constraint)
        for constraint in constraints
        if constraint.constraint_type == "Equipment" and constraint.hard and constraint.negated
    }

    for edge in graph.outgoing(exercise_id, "REQUIRES"):
        equipment_value = edge.target.split(":", 1)[1]
        if edge.target not in available_equipment:
            reasons.append(
                SafetyReason(
                    severity="EQUIPMENT_HARD_BLOCK",
                    reason_code=f"MISSING_EQUIPMENT:{equipment_value}",
                    graph_paths=(edge.path(),),
                )
            )
        if edge.target in disallowed_equipment:
            reasons.append(
                SafetyReason(
                    severity="EQUIPMENT_HARD_BLOCK",
                    reason_code=f"DISALLOWED_EQUIPMENT:{equipment_value}",
                    graph_paths=(edge.path(),),
                )
            )
    return reasons


def _prompt_exclusion_reasons(
    exercise_id: str,
    graph: LocalGraph,
    constraints: tuple[ResolvedConstraint, ...],
) -> list[SafetyReason]:
    reasons: list[SafetyReason] = []
    excluded_families = {
        _constraint_node_id(constraint)
        for constraint in constraints
        if constraint.constraint_type == "ExerciseFamily" and constraint.hard and constraint.negated
    }
    if not excluded_families:
        return reasons

    for edge in graph.outgoing(exercise_id, "VARIANT_OF"):
        if edge.target in excluded_families:
            family_value = edge.target.split(":", 1)[1]
            reasons.append(
                SafetyReason(
                    severity="PROMPT_EXCLUSION",
                    reason_code=f"PROMPT_EXCLUDED_FAMILY:{family_value}",
                    graph_paths=(edge.path(),),
                )
            )
    return reasons


def _receipt(
    exercise_id: str,
    reasons: list[SafetyReason],
    available_equipment: frozenset[str],
    constraints: tuple[ResolvedConstraint, ...],
) -> DecisionReceipt:
    if reasons:
        severity = primary_severity([reason.severity for reason in reasons])
        if severity is None:
            severity = "SOFT_PENALTY"
        primary_reason = next(reason for reason in reasons if reason.severity == severity)
        decision = "filtered" if severity in HARD_BLOCK_SEVERITIES else "downranked"
        reason_codes = tuple(reason.reason_code for reason in reasons)
        graph_paths = tuple(path for reason in reasons for path in reason.graph_paths)
        primary_reason_code = primary_reason.reason_code
    else:
        severity = "BOOST"
        decision = "selected"
        reason_codes = ("PASSED_SAFETY",)
        graph_paths = ()
        primary_reason_code = "PASSED_SAFETY"

    fingerprint = stable_fingerprint(
        {
            "available_equipment": sorted(available_equipment),
            "constraints": [
                {
                    "constraint_type": constraint.constraint_type,
                    "value": constraint.value,
                    "hard": constraint.hard,
                    "negated": constraint.negated,
                    "source_text": constraint.source_text,
                }
                for constraint in constraints
            ],
            "exercise_id": exercise_id,
        }
    )
    return DecisionReceipt(
        exercise_id=exercise_id,
        decision=decision,
        primary_severity=severity,
        reason_codes=reason_codes,
        primary_reason_code=primary_reason_code,
        graph_paths=graph_paths,
        constraint_fingerprint=fingerprint,
        graph_version=GRAPH_VERSION,
        ruleset_version=RULESET_VERSION,
        ontology_lock_version=ONTOLOGY_LOCK_VERSION,
    )


def evaluate_candidates(
    candidate_ids: Iterable[str] | None = None,
    *,
    available_equipment: Iterable[str],
    constraints: Iterable[ResolvedConstraint] = (),
    graph: LocalGraph | None = None,
    safety_rules: tuple[SafetyRule, ...] | None = None,
) -> list[DecisionReceipt]:
    """Evaluate candidate exercises using local graph facts and typed constraints."""

    local_graph = graph if graph is not None else load_local_graph()
    rules = safety_rules if safety_rules is not None else load_safety_rules()
    available = _equipment_ids(available_equipment)
    resolved_constraints = tuple(constraints)
    exercises = (
        tuple(candidate_ids)
        if candidate_ids is not None
        else tuple(sorted(node.id for node in local_graph.nodes_by_type("Exercise")))
    )

    receipts: list[DecisionReceipt] = []
    for exercise_id in exercises:
        local_graph.node(exercise_id)
        reasons = [
            *_medical_reasons(exercise_id, local_graph, resolved_constraints, rules),
            *_equipment_reasons(exercise_id, local_graph, available, resolved_constraints),
            *_prompt_exclusion_reasons(exercise_id, local_graph, resolved_constraints),
        ]
        receipts.append(_receipt(exercise_id, reasons, available, resolved_constraints))
    return receipts
