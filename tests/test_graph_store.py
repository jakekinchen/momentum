from __future__ import annotations

from kg.graph_store import GRAPH_DIR, load_json, load_local_graph


def test_local_graph_loads_m1_seed_nodes_and_edges() -> None:
    graph = load_local_graph()

    assert graph.node("BodyRegion:knee").type == "BodyRegion"
    assert graph.node("Equipment:kettlebell").type == "Equipment"
    assert graph.node("ExerciseFamily:deadlift_family").type == "ExerciseFamily"
    assert len(graph.incoming("BodyRegion:knee", "PART_OF")) >= 3


def test_knee_part_of_closure_uses_local_runtime_edges_only() -> None:
    graph = load_local_graph()

    closure = graph.descendants_by_incoming_part_of("BodyRegion:knee")
    closure_ids = {node.id for node in closure}
    paths = graph.part_of_closure_paths("BodyRegion:knee")

    assert "BodyRegion:knee" in closure_ids
    assert "BodyRegion:left_knee" in closure_ids
    assert "BodyRegion:knee_joint" in closure_ids
    assert "BodyRegion:patella" in closure_ids
    assert paths
    assert all("-PART_OF->" in path for path in paths)
    assert all("MAPS_TO" not in path for path in paths)


def test_ontology_mappings_remain_unverified_audit_records() -> None:
    payload = load_json(GRAPH_DIR / "ontology_mappings.seed.json")

    assert payload["runtime_policy"]["maps_to_edges_are_safety_edges"] is False
    assert payload["runtime_policy"]["vector_search_for_safety_enforcement"] is False
    assert all(concept["external_id"] is None for concept in payload["ontology_concepts"])
    assert all(mapping["predicate"] == "MAPS_TO" for mapping in payload["mappings"])
    assert all("local_term_id" in mapping for mapping in payload["mappings"])
    assert all("ontology_concept_id" in mapping for mapping in payload["mappings"])
    assert all(mapping["source"] == "ontology_mappings.seed.json" for mapping in payload["mappings"])
