from __future__ import annotations

from kg.provenance import validate_decision_receipt
from kg.safety import evaluate_candidates


def test_decision_receipt_satisfies_minimal_prov_shape() -> None:
    [receipt] = evaluate_candidates(
        ["Exercise:glute_bridge"],
        available_equipment={"Equipment:yoga_mat"},
    )

    assert validate_decision_receipt(receipt) == []


def test_decision_receipt_validation_rejects_missing_required_field() -> None:
    payload = {
        "exercise_id": "Exercise:glute_bridge",
        "decision": "selected",
        "primary_severity": "BOOST",
        "reason_codes": ("PASSED_SAFETY",),
        "primary_reason_code": "PASSED_SAFETY",
        "graph_paths": (),
        "constraint_fingerprint": "abc123",
        "ruleset_version": "ruleset-m2-safety-v0",
        "ontology_lock_version": "ontology-lock-m0-unverified",
    }

    errors = validate_decision_receipt(payload)

    assert "DecisionReceipt missing required field: graph_version" in errors
