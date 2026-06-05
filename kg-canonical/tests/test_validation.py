from __future__ import annotations

from copy import deepcopy
import json
import subprocess
import sys

from kg.graph_store import GRAPH_DIR, load_json
from kg.validation import (
    REQUIRED_SEED_FILES,
    health_summary,
    ontology_sidecar_text_export,
    schema_validation_findings,
    validate_graph_seed,
    validate_ontology_lock,
    validate_ontology_mapping_seed,
)


def test_health_summary_reports_required_seed_files() -> None:
    summary = health_summary()

    assert summary["graph_version"] == "fitgraph-kg-m5-validation-v0"
    assert summary["ruleset_version"] == "ruleset-m2-safety-v0"
    assert summary["ontology_lock_version"] == "ontology-lock-m0-unverified"
    assert summary["ontology_status"] == "todo_unverified"
    assert summary["verified"] is False
    assert summary["validation_status"] == "pass"
    assert summary["schema_validation_status"] == "pass"
    assert summary["schema_validation_errors"] == []
    assert summary["ontology_sidecar_export_status"] == "available_unverified"
    assert summary["ontology_sidecar_line_count"] > 0
    assert summary["required_seed_count"] == len(REQUIRED_SEED_FILES)
    assert summary["present_seed_count"] == len(REQUIRED_SEED_FILES)
    assert summary["parseable_seed_count"] == len(REQUIRED_SEED_FILES)
    assert set(summary["seed_files"]) == set(REQUIRED_SEED_FILES)


def test_schema_validation_findings_report_current_seeds_as_passing() -> None:
    findings = schema_validation_findings()

    assert {finding["status"] for finding in findings} == {"pass"}
    assert {finding["check"] for finding in findings} == {
        "required_seed_files_parse_as_json_objects",
        "graph_seed_node_and_edge_schema",
        "ontology_mapping_seed_schema",
        "ontology_lock_truthfulness",
    }


def test_invalid_graph_edge_reference_fails_validation() -> None:
    payload = deepcopy(load_json(GRAPH_DIR / "exercise_kg.seed.json"))
    payload["edges"][0]["target"] = "BodyRegion:missing"

    errors = validate_graph_seed(payload, "bad_exercise_kg.seed.json")

    assert "bad_exercise_kg.seed.json: edge target is missing: BodyRegion:missing" in errors


def test_duplicate_graph_node_ids_fail_validation() -> None:
    payload = deepcopy(load_json(GRAPH_DIR / "exercise_kg.seed.json"))
    payload["nodes"].append(deepcopy(payload["nodes"][0]))

    errors = validate_graph_seed(payload, "bad_exercise_kg.seed.json")

    assert "bad_exercise_kg.seed.json: duplicate node id BodyRegion:knee" in errors


def test_ontology_mapping_seed_preserves_audit_only_policy() -> None:
    payload = load_json(GRAPH_DIR / "ontology_mappings.seed.json")

    assert validate_ontology_mapping_seed(payload) == []

    bad_payload = deepcopy(payload)
    bad_payload["runtime_policy"]["maps_to_edges_are_safety_edges"] = True
    bad_payload["mappings"][0].pop("source")

    errors = validate_ontology_mapping_seed(bad_payload)

    assert "ontology_mappings.seed.json: MAPS_TO must not be treated as a runtime safety edge" in errors
    assert "ontology_mappings.seed.json: mappings[0].source must be a non-empty string" in errors


def test_ontology_lock_cannot_report_verified_without_pinned_values() -> None:
    payload = load_json(GRAPH_DIR / "ontology-lock.json")

    assert validate_ontology_lock(payload) == []

    bad_payload = deepcopy(payload)
    bad_payload["verified"] = True
    bad_payload["status"] = "verified"

    errors = validate_ontology_lock(bad_payload)

    assert "ontology-lock.json: verified=true requires pinned ontology concept IDs" in errors
    assert (
        "ontology-lock.json: status must remain explicitly unverified until concept IDs are pinned"
        in errors
    )


def test_ontology_sidecar_text_export_marks_concepts_unverified() -> None:
    export = ontology_sidecar_text_export()

    assert "# verified: false" in export
    assert "verification_status=unverified" in export
    assert "external_id=unverified" in export
    assert "LocalTerm:knee MAPS_TO OntologyConcept:unverified_knee_region" in export


def test_validation_module_is_reachable_as_command() -> None:
    result = subprocess.run(
        [sys.executable, "-m", "kg.validation"],
        check=True,
        capture_output=True,
        text=True,
    )
    summary = json.loads(result.stdout)

    assert summary["validation_status"] == "pass"
    assert summary["schema_validation_status"] == "pass"
    assert summary["present_seed_count"] == len(REQUIRED_SEED_FILES)
