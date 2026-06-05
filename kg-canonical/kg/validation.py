"""Deterministic health checks for the FitGraph KG local graph."""

from __future__ import annotations

from dataclasses import asdict
import json
from pathlib import Path
import sys
from typing import Any

from kg.graph_store import GRAPH_DIR, SeedArtifact, inspect_seed_artifact, load_json


GRAPH_VERSION = "fitgraph-kg-m5-validation-v0"
RULESET_VERSION = "ruleset-m2-safety-v0"
REQUIRED_SEED_FILES: tuple[str, ...] = (
    "exercise_kg.seed.json",
    "member_kg.seed.json",
    "ontology_mappings.seed.json",
    "safety_rules.seed.json",
    "provenance_schema.json",
    "ontology-lock.json",
)
GRAPH_SEED_FILES: tuple[str, ...] = (
    "exercise_kg.seed.json",
    "member_kg.seed.json",
)
ONTOLOGY_MAPPING_SEED_FILE = "ontology_mappings.seed.json"
ONTOLOGY_LOCK_FILE = "ontology-lock.json"
REQUIRED_GRAPH_NODE_FIELDS: tuple[str, ...] = ("id", "type", "label")
REQUIRED_GRAPH_EDGE_FIELDS: tuple[str, ...] = ("source", "predicate", "target")
REQUIRED_MAPPING_FIELDS: tuple[str, ...] = (
    "local_term_id",
    "ontology_concept_id",
    "skos_predicate",
    "method",
    "review_status",
    "source",
)
ALLOWED_SKOS_PREDICATES = frozenset(
    {
        "exactMatch",
        "closeMatch",
        "broadMatch",
        "narrowMatch",
        "relatedMatch",
    }
)


def _artifact_payload(artifact: SeedArtifact) -> dict[str, Any]:
    payload = asdict(artifact)
    payload["path"] = str(artifact.path)
    return payload


def _dedupe(errors: list[str]) -> list[str]:
    seen: set[str] = set()
    unique: list[str] = []
    for error in errors:
        if error not in seen:
            seen.add(error)
            unique.append(error)
    return unique


def _has_text(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _load_payload_for_validation(
    name: str,
    graph_dir: Path,
) -> tuple[dict[str, Any] | None, list[str]]:
    try:
        return load_json(graph_dir / name), []
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return None, [f"{name}: {exc}"]


def _ontology_lock_metadata(graph_dir: Path) -> dict[str, Any]:
    path = graph_dir / ONTOLOGY_LOCK_FILE
    if not path.exists():
        return {
            "ontology_lock_version": "missing",
            "ontology_status": "missing",
            "verified": False,
        }

    payload = load_json(path)
    verified_value = payload.get("verified", False)
    return {
        "ontology_lock_version": str(payload.get("ontology_lock_version", "unknown")),
        "ontology_status": str(payload.get("status", "unknown")),
        "verified": verified_value if isinstance(verified_value, bool) else False,
    }


def validate_required_seed_files(graph_dir: Path = GRAPH_DIR) -> list[str]:
    """Validate required seed files exist and parse as JSON objects."""

    errors: list[str] = []
    for name in REQUIRED_SEED_FILES:
        path = graph_dir / name
        if not path.exists():
            errors.append(f"{name}: missing required seed file")
            continue
        try:
            load_json(path)
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            errors.append(f"{name}: {exc}")
    return errors


def validate_graph_seed(payload: dict[str, Any], name: str = "graph seed") -> list[str]:
    """Validate local runtime graph node and edge shape."""

    errors: list[str] = []
    nodes = payload.get("nodes")
    edges = payload.get("edges")
    if not isinstance(nodes, list):
        errors.append(f"{name}: nodes must be a list")
        nodes = []
    if not isinstance(edges, list):
        errors.append(f"{name}: edges must be a list")
        edges = []

    node_ids: set[str] = set()
    for index, node in enumerate(nodes):
        location = f"{name}: nodes[{index}]"
        if not isinstance(node, dict):
            errors.append(f"{location} must be an object")
            continue
        for field in REQUIRED_GRAPH_NODE_FIELDS:
            if not _has_text(node.get(field)):
                errors.append(f"{location}.{field} must be a non-empty string")
        node_id = node.get("id")
        if _has_text(node_id):
            if node_id in node_ids:
                errors.append(f"{name}: duplicate node id {node_id}")
            node_ids.add(node_id)

    for index, edge in enumerate(edges):
        location = f"{name}: edges[{index}]"
        if not isinstance(edge, dict):
            errors.append(f"{location} must be an object")
            continue
        for field in REQUIRED_GRAPH_EDGE_FIELDS:
            if not _has_text(edge.get(field)):
                errors.append(f"{location}.{field} must be a non-empty string")

        source = edge.get("source")
        target = edge.get("target")
        predicate = edge.get("predicate")
        if _has_text(source) and source not in node_ids:
            errors.append(f"{name}: edge source is missing: {source}")
        if _has_text(target) and target not in node_ids:
            errors.append(f"{name}: edge target is missing: {target}")
        if predicate == "MAPS_TO":
            properties = edge.get("properties", {})
            if not isinstance(properties, dict) or properties.get("runtime_safety_edge") is not False:
                errors.append(f"{location}: MAPS_TO must not be a runtime safety edge")
    return errors


def validate_ontology_mapping_seed(
    payload: dict[str, Any],
    name: str = ONTOLOGY_MAPPING_SEED_FILE,
) -> list[str]:
    """Validate SKOS-style audit mappings without promoting them to safety edges."""

    errors: list[str] = []
    local_terms = payload.get("local_terms")
    ontology_concepts = payload.get("ontology_concepts")
    mappings = payload.get("mappings")
    runtime_policy = payload.get("runtime_policy", {})

    if not isinstance(local_terms, list):
        errors.append(f"{name}: local_terms must be a list")
        local_terms = []
    if not isinstance(ontology_concepts, list):
        errors.append(f"{name}: ontology_concepts must be a list")
        ontology_concepts = []
    if not isinstance(mappings, list):
        errors.append(f"{name}: mappings must be a list")
        mappings = []
    if not isinstance(runtime_policy, dict):
        errors.append(f"{name}: runtime_policy must be an object")
        runtime_policy = {}

    if runtime_policy.get("maps_to_edges_are_safety_edges") is not False:
        errors.append(f"{name}: MAPS_TO must not be treated as a runtime safety edge")
    if runtime_policy.get("vector_search_for_safety_enforcement") is not False:
        errors.append(f"{name}: vector search must not enforce safety")

    local_term_ids: set[str] = set()
    for index, term in enumerate(local_terms):
        location = f"{name}: local_terms[{index}]"
        if not isinstance(term, dict):
            errors.append(f"{location} must be an object")
            continue
        for field in REQUIRED_GRAPH_NODE_FIELDS:
            if not _has_text(term.get(field)):
                errors.append(f"{location}.{field} must be a non-empty string")
        term_id = term.get("id")
        if _has_text(term_id):
            local_term_ids.add(term_id)

    ontology_concept_ids: set[str] = set()
    for index, concept in enumerate(ontology_concepts):
        location = f"{name}: ontology_concepts[{index}]"
        if not isinstance(concept, dict):
            errors.append(f"{location} must be an object")
            continue
        for field in REQUIRED_GRAPH_NODE_FIELDS:
            if not _has_text(concept.get(field)):
                errors.append(f"{location}.{field} must be a non-empty string")
        concept_id = concept.get("id")
        if _has_text(concept_id):
            ontology_concept_ids.add(concept_id)
        if concept.get("verification_status") == "verified" and not _has_text(
            concept.get("external_id")
        ):
            errors.append(f"{location}: verified concepts require an external_id")

    for index, mapping in enumerate(mappings):
        location = f"{name}: mappings[{index}]"
        if not isinstance(mapping, dict):
            errors.append(f"{location} must be an object")
            continue
        for field in REQUIRED_MAPPING_FIELDS:
            if not _has_text(mapping.get(field)):
                errors.append(f"{location}.{field} must be a non-empty string")
        if mapping.get("predicate") != "MAPS_TO":
            errors.append(f"{location}.predicate must be MAPS_TO")
        if mapping.get("runtime_safety_edge") is True:
            errors.append(f"{location}: MAPS_TO must not be a runtime safety edge")

        local_term_id = mapping.get("local_term_id")
        ontology_concept_id = mapping.get("ontology_concept_id")
        skos_predicate = mapping.get("skos_predicate")
        if _has_text(local_term_id) and local_term_id not in local_term_ids:
            errors.append(f"{location}.local_term_id is unknown: {local_term_id}")
        if _has_text(ontology_concept_id) and ontology_concept_id not in ontology_concept_ids:
            errors.append(f"{location}.ontology_concept_id is unknown: {ontology_concept_id}")
        if _has_text(skos_predicate) and skos_predicate not in ALLOWED_SKOS_PREDICATES:
            errors.append(f"{location}.skos_predicate is not supported: {skos_predicate}")
    return errors


def validate_ontology_lock(payload: dict[str, Any], name: str = ONTOLOGY_LOCK_FILE) -> list[str]:
    """Validate the ontology lockfile does not claim unpinned facts as verified."""

    errors: list[str] = []
    status = str(payload.get("status", ""))
    verified_value = payload.get("verified", False)
    if not isinstance(verified_value, bool):
        errors.append(f"{name}: verified must be a boolean")
        verified = False
    else:
        verified = verified_value

    ontologies = payload.get("ontologies")
    if not isinstance(ontologies, dict):
        errors.append(f"{name}: ontologies must be an object")
        ontologies = {}

    pinned_ids: list[str] = []
    for ontology_name, ontology in sorted(ontologies.items()):
        location = f"{name}: ontologies.{ontology_name}"
        if not isinstance(ontology, dict):
            errors.append(f"{location} must be an object")
            continue
        concept_ids = ontology.get("concept_ids")
        if not isinstance(concept_ids, list):
            errors.append(f"{location}.concept_ids must be a list")
            concept_ids = []
        local_pinned_ids = [concept_id for concept_id in concept_ids if _has_text(concept_id)]
        pinned_ids.extend(local_pinned_ids)

        ontology_status = str(ontology.get("status", ""))
        if ontology_status == "verified" and not local_pinned_ids:
            errors.append(f"{location}: verified status requires pinned concept_ids")
        if ontology.get("license_status") not in (None, "unverified") and not local_pinned_ids:
            errors.append(f"{location}: license_status cannot be claimed without concept_ids")
        if ontology.get("release_id") is not None and not local_pinned_ids:
            errors.append(f"{location}: release_id cannot be claimed without concept_ids")
        if ontology.get("accessed_at") is not None and not local_pinned_ids:
            errors.append(f"{location}: accessed_at cannot be claimed without concept_ids")

    if verified and not pinned_ids:
        errors.append(f"{name}: verified=true requires pinned ontology concept IDs")
    if "unverified" not in status.lower() and not pinned_ids:
        errors.append(f"{name}: status must remain explicitly unverified until concept IDs are pinned")

    runtime_policy = payload.get("runtime_policy", {})
    if not isinstance(runtime_policy, dict):
        errors.append(f"{name}: runtime_policy must be an object")
        runtime_policy = {}
    if runtime_policy.get("local_taxonomy_authoritative_for_runtime_behavior") is not True:
        errors.append(f"{name}: local taxonomy must remain authoritative for runtime behavior")
    if runtime_policy.get("maps_to_edges_are_safety_edges") is not False:
        errors.append(f"{name}: MAPS_TO must not be treated as a runtime safety edge")
    if runtime_policy.get("vector_search_for_safety_enforcement") is not False:
        errors.append(f"{name}: vector search must not enforce safety")
    if runtime_policy.get("llm_decides_safety") is not False:
        errors.append(f"{name}: LLMs must not decide safety")
    return errors


def schema_validation_findings(graph_dir: Path = GRAPH_DIR) -> tuple[dict[str, Any], ...]:
    """Return pass/fail findings for current seed schema checks."""

    required_errors = validate_required_seed_files(graph_dir)

    graph_errors: list[str] = []
    for name in GRAPH_SEED_FILES:
        payload, load_errors = _load_payload_for_validation(name, graph_dir)
        graph_errors.extend(load_errors)
        if payload is not None:
            graph_errors.extend(validate_graph_seed(payload, name))

    mapping_payload, mapping_load_errors = _load_payload_for_validation(
        ONTOLOGY_MAPPING_SEED_FILE,
        graph_dir,
    )
    mapping_errors = list(mapping_load_errors)
    if mapping_payload is not None:
        mapping_errors.extend(validate_ontology_mapping_seed(mapping_payload))

    lock_payload, lock_load_errors = _load_payload_for_validation(ONTOLOGY_LOCK_FILE, graph_dir)
    lock_errors = list(lock_load_errors)
    if lock_payload is not None:
        lock_errors.extend(validate_ontology_lock(lock_payload))

    checks: tuple[tuple[str, list[str]], ...] = (
        ("required_seed_files_parse_as_json_objects", required_errors),
        ("graph_seed_node_and_edge_schema", graph_errors),
        ("ontology_mapping_seed_schema", mapping_errors),
        ("ontology_lock_truthfulness", lock_errors),
    )
    return tuple(
        {
            "check": check,
            "status": "pass" if not errors else "fail",
            "errors": _dedupe(errors),
        }
        for check, errors in checks
    )


def ontology_sidecar_text_export(graph_dir: Path = GRAPH_DIR) -> str:
    """Return a deterministic text sidecar that keeps ontology concepts unverified."""

    mappings_payload = load_json(graph_dir / ONTOLOGY_MAPPING_SEED_FILE)
    lock_payload = load_json(graph_dir / ONTOLOGY_LOCK_FILE)
    concepts = {
        str(concept["id"]): concept
        for concept in mappings_payload.get("ontology_concepts", [])
        if isinstance(concept, dict) and _has_text(concept.get("id"))
    }
    mappings = [
        mapping
        for mapping in mappings_payload.get("mappings", [])
        if isinstance(mapping, dict)
    ]

    lines = [
        "# FitGraph ontology sidecar text export",
        f"# ontology_lock_version: {lock_payload.get('ontology_lock_version', 'unknown')}",
        f"# ontology_status: {lock_payload.get('status', 'unknown')}",
        f"# verified: {str(lock_payload.get('verified', False)).lower()}",
        "# external ontology concepts are unverified unless pinned in graph/ontology-lock.json",
    ]
    for mapping in sorted(
        mappings,
        key=lambda item: (
            str(item.get("local_term_id", "")),
            str(item.get("ontology_concept_id", "")),
        ),
    ):
        concept = concepts.get(str(mapping.get("ontology_concept_id")), {})
        external_id = concept.get("external_id")
        external_id_text = str(external_id) if _has_text(external_id) else "unverified"
        lines.append(
            " | ".join(
                (
                    f"{mapping.get('local_term_id')} MAPS_TO {mapping.get('ontology_concept_id')}",
                    f"skos={mapping.get('skos_predicate')}",
                    f"verification_status={concept.get('verification_status', 'unknown')}",
                    f"external_ontology={concept.get('external_ontology', 'unknown')}",
                    f"external_id={external_id_text}",
                    f"source={mapping.get('source')}",
                    f"review_status={mapping.get('review_status')}",
                )
            )
        )
    return "\n".join(lines)


def health_summary(graph_dir: Path = GRAPH_DIR) -> dict[str, Any]:
    """Return deterministic seed-file and version health for the local graph."""

    artifacts = [inspect_seed_artifact(name, graph_dir) for name in REQUIRED_SEED_FILES]
    seed_files = {artifact.name: _artifact_payload(artifact) for artifact in artifacts}
    validation_errors = [
        f"{artifact.name}: {artifact.error or artifact.status}"
        for artifact in artifacts
        if not artifact.exists or not artifact.parse_ok
    ]

    try:
        ontology_metadata = _ontology_lock_metadata(graph_dir)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        ontology_metadata = {
            "ontology_lock_version": "invalid",
            "ontology_status": "invalid",
            "verified": False,
        }
        validation_errors.append(f"ontology-lock.json: {exc}")

    findings = schema_validation_findings(graph_dir)
    schema_errors = _dedupe(
        [error for finding in findings for error in finding.get("errors", [])]
    )
    validation_errors = _dedupe([*validation_errors, *schema_errors])

    try:
        sidecar_line_count = len(ontology_sidecar_text_export(graph_dir).splitlines())
        sidecar_export_status = "available_unverified"
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        sidecar_line_count = 0
        sidecar_export_status = "unavailable"
        validation_errors = _dedupe(
            [*validation_errors, f"ontology sidecar export unavailable: {exc}"]
        )

    return {
        "graph_version": GRAPH_VERSION,
        "ruleset_version": RULESET_VERSION,
        **ontology_metadata,
        "validation_status": "pass" if not validation_errors else "fail",
        "validation_errors": validation_errors,
        "schema_validation_status": "pass" if not schema_errors else "fail",
        "schema_validation_errors": schema_errors,
        "validation_findings": findings,
        "ontology_sidecar_export_status": sidecar_export_status,
        "ontology_sidecar_line_count": sidecar_line_count,
        "graph_dir": str(graph_dir),
        "required_seed_count": len(REQUIRED_SEED_FILES),
        "present_seed_count": sum(1 for artifact in artifacts if artifact.exists),
        "parseable_seed_count": sum(1 for artifact in artifacts if artifact.parse_ok),
        "node_count": sum(artifact.node_count for artifact in artifacts),
        "edge_count": sum(artifact.edge_count for artifact in artifacts),
        "seed_files": seed_files,
    }


def main() -> int:
    """Print graph health as JSON and return non-zero on failed validation."""

    summary = health_summary()
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0 if summary["validation_status"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
