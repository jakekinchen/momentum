from __future__ import annotations

import json
import subprocess
import sys

import pytest

from kg.assessment_import import (
    ASSESSMENT_DATA_SOURCE_ROOT,
    SOURCE_SNAPSHOT_COMMIT,
    build_assessment_import_artifacts,
)
from kg.validation import validate_graph_seed


REQUIRED_SOURCE_SPAN_PROPERTIES = {
    "source_file",
    "json_path",
    "source_hash",
    "source_snapshot_commit",
    "synthetic_data",
}
REQUIRED_STRESS_PROPERTIES = {
    "loaded",
    "load_level",
    "impact_level",
    "flexion_depth",
    "axial_load",
    "balance_demand",
    "laterality",
}
ALLOWED_STRESS_VALUES = {
    "load_level": {"low", "medium", "high"},
    "impact_level": {"low", "medium", "high"},
    "flexion_depth": {"none", "limited", "moderate", "deep"},
    "axial_load": {"none", "low", "medium", "high"},
    "balance_demand": {"low", "medium", "high"},
    "laterality": {
        "left",
        "right",
        "bilateral",
        "neutral",
        "left_arm",
        "right_arm",
        "left_leg",
        "right_leg",
        "left_side",
        "right_side",
    },
}
RELATION_TARGET_PREDICATES = {"REQUIRES", "TARGETS", "HAS_PATTERN", "VARIANT_OF"}


def test_assessment_import_preserves_fixture_counts_and_source_hashes() -> None:
    artifacts = build_assessment_import_artifacts()
    summary = artifacts.conformance_summary

    assert summary["status"] == "pass"
    assert summary["actual_counts"] == {
        "exercise_count": 50,
        "muscle_group_count": 19,
        "loaded_body_region_count": 9,
        "movement_pattern_count": 36,
        "equipment_count": 32,
    }
    assert summary["expected_counts"] == summary["actual_counts"]
    assert summary["source_snapshot_commit"] == SOURCE_SNAPSHOT_COMMIT
    assert len(summary["exercise_source_sha256"]) == 64
    assert len(summary["member_source_sha256"]) == 64
    assert summary["all_exercise_records_preserved"] is True
    assert summary["member_sections_missing"] == []
    assert summary["synthetic_data_only"] is True


def test_assessment_exercise_graph_is_valid_and_source_backed() -> None:
    artifacts = build_assessment_import_artifacts()
    graph = artifacts.exercise_graph
    nodes = {node["id"]: node for node in graph["nodes"]}
    edges = graph["edges"]

    assert validate_graph_seed(graph, "assessment_exercise_kg.generated.json") == []
    assert len([node for node in nodes.values() if node["type"] == "Exercise"]) == 50
    assert nodes["Exercise:kettlebell_goblet_cyclist_squat"]["properties"]["source_fields"][
        "equipment_required"
    ] == ["Kettlebell", "Slant Board"]
    assert any(
        edge["source"] == "Exercise:kettlebell_goblet_cyclist_squat"
        and edge["predicate"] == "STRESSES"
        and edge["target"] == "BodyRegion:knee"
        and edge["properties"]["flexion_depth"] == "deep"
        for edge in edges
    )
    assert any(
        edge["source"] == "Exercise:vertical_jump_to_broad_jump"
        and edge["predicate"] == "STRESSES"
        and edge["properties"]["impact_level"] == "high"
        for edge in edges
    )
    assert any(
        edge["source"] == "Exercise:barbell_racked_forward_lunge"
        and edge["predicate"] == "REQUIRES"
        and edge["target"] == "Equipment:barbell"
        for edge in edges
    )
    assert any(
        edge["source"] == "Exercise:dumbbell_goblet_split_squat"
        and edge["predicate"] == "VARIANT_OF"
        and edge["target"] == "ExerciseFamily:lunge_family"
        for edge in edges
    )
    assert any(
        edge["source"] == "Exercise:static_jump"
        and edge["predicate"] == "VARIANT_OF"
        and edge["target"] == "ExerciseFamily:jump_family"
        for edge in edges
    )
    assert nodes["SourceSpan:assessment_exercise_019"]["properties"]["json_path"] == "$[19]"
    assert nodes["SourceSpan:assessment_exercise_019"]["properties"]["synthetic_data"] is True


def test_every_imported_exercise_is_derived_from_source_span() -> None:
    graph = build_assessment_import_artifacts().exercise_graph
    nodes = {node["id"]: node for node in graph["nodes"]}
    source_spans = {
        node_id
        for node_id, node in nodes.items()
        if node["type"] == "SourceSpan"
    }
    derived_from = {
        edge["source"]: edge["target"]
        for edge in graph["edges"]
        if edge["predicate"] == "DERIVED_FROM"
    }

    exercise_ids = sorted(
        node_id
        for node_id, node in nodes.items()
        if node["type"] == "Exercise"
    )
    assert len(exercise_ids) == 50
    assert sorted(derived_from) == exercise_ids
    assert all(derived_from[exercise_id] in source_spans for exercise_id in exercise_ids)


def test_all_generated_source_spans_have_required_provenance_properties() -> None:
    artifacts = build_assessment_import_artifacts()

    for graph in (artifacts.exercise_graph, artifacts.member_graph):
        source_spans = [
            node
            for node in graph["nodes"]
            if node["type"] == "SourceSpan"
        ]
        assert source_spans
        for node in source_spans:
            properties = node["properties"]
            assert REQUIRED_SOURCE_SPAN_PROPERTIES <= properties.keys()
            assert properties["source_file"].startswith(f"{ASSESSMENT_DATA_SOURCE_ROOT}/")
            assert properties["json_path"]
            assert len(properties["source_hash"]) == 64
            assert properties["source_snapshot_commit"] == SOURCE_SNAPSHOT_COMMIT
            assert properties["synthetic_data"] is True


def test_all_stress_edges_have_required_properties_with_allowed_values() -> None:
    graph = build_assessment_import_artifacts().exercise_graph
    stress_edges = [
        edge
        for edge in graph["edges"]
        if edge["predicate"] == "STRESSES"
    ]

    assert stress_edges
    for edge in stress_edges:
        properties = edge["properties"]
        assert REQUIRED_STRESS_PROPERTIES <= properties.keys()
        assert isinstance(properties["loaded"], bool)
        for key, allowed_values in ALLOWED_STRESS_VALUES.items():
            assert properties[key] in allowed_values


def test_exercise_relation_targets_exist_for_all_imported_records() -> None:
    graph = build_assessment_import_artifacts().exercise_graph
    node_ids = {node["id"] for node in graph["nodes"]}
    relation_edges = [
        edge
        for edge in graph["edges"]
        if edge["predicate"] in RELATION_TARGET_PREDICATES
    ]

    assert relation_edges
    for edge in relation_edges:
        assert edge["source"] in node_ids
        assert edge["target"] in node_ids


def test_high_impact_jump_records_have_high_impact_knee_stress_edge() -> None:
    graph = build_assessment_import_artifacts().exercise_graph
    nodes = {node["id"]: node for node in graph["nodes"]}
    stress_edges_by_source: dict[str, list[dict[str, object]]] = {}
    for edge in graph["edges"]:
        if edge["predicate"] == "STRESSES":
            stress_edges_by_source.setdefault(edge["source"], []).append(edge)

    high_impact_exercise_ids = []
    for node_id, node in nodes.items():
        if node["type"] != "Exercise":
            continue
        source_fields = node["properties"]["source_fields"]
        text = (
            f"{source_fields.get('name', '')} "
            f"{' '.join(source_fields.get('movement_patterns', []))}"
        ).lower()
        if "jump" in text or "plyometric" in text:
            high_impact_exercise_ids.append(node_id)

    assert sorted(high_impact_exercise_ids) == [
        "Exercise:bosu_step_over",
        "Exercise:jump_rope_single_leg",
        "Exercise:jumping_jack",
        "Exercise:med_ball_scoop_toss",
        "Exercise:static_jump",
        "Exercise:vertical_jump_to_broad_jump",
    ]
    for exercise_id in high_impact_exercise_ids:
        assert any(
            edge["target"] == "BodyRegion:knee"
            and edge["properties"]["impact_level"] == "high"
            for edge in stress_edges_by_source[exercise_id]
        )


def test_assessment_member_graph_represents_all_required_member_context() -> None:
    artifacts = build_assessment_import_artifacts()
    graph = artifacts.member_graph
    nodes = {node["id"]: node for node in graph["nodes"]}
    node_types = {node["type"] for node in nodes.values()}

    assert validate_graph_seed(graph, "assessment_member_kg.generated.json") == []
    assert {
        "Member",
        "Goal",
        "Preference",
        "EquipmentAvailability",
        "InjuryEpisode",
        "Restriction",
        "WorkoutSession",
        "ExercisePerformance",
        "AdherenceObservation",
        "BiomarkerObservation",
        "LabResult",
        "Message",
        "Attachment",
        "CoachBrief",
        "CoachTask",
        "ChurnSignal",
        "SourceSpan",
    } <= node_types
    assert nodes["Member:jordan"]["label"] == "Jordan Rivera"
    assert nodes["EquipmentAvailability:jordan_home_equipment_assessment"]["properties"][
        "equipment_ids"
    ] == [
        "Equipment:dumbbell",
        "Equipment:kettlebell",
        "Equipment:yoga_mat",
        "Equipment:resistance_band_loop",
        "Equipment:flat_bench",
    ]
    assert nodes["InjuryEpisode:inj_knee_left"]["properties"]["region_id"] == "BodyRegion:left_knee"
    assert nodes["Preference:jordan_training_preferences"]["properties"]["dislikes"] == [
        "Deadlift",
        "Burpees",
    ]
    assert (
        nodes["Preference:jordan_training_preferences"]["properties"][
            "preferred_session_minutes"
        ]
        == 50
    )
    assert len([node for node in nodes.values() if node["type"] == "AdherenceObservation"]) == 4
    biomarker_metrics = {
        node["properties"]["metric"]
        for node in nodes.values()
        if node["type"] == "BiomarkerObservation"
    }
    assert {"sleep_hours", "resting_hr_bpm", "hrv_ms", "weight_kg"} <= biomarker_metrics
    assert len([node for node in nodes.values() if node["type"] == "Message"]) == 4
    assert len([node for node in nodes.values() if node["type"] == "LabResult"]) >= 12
    assert nodes["LabResult:jordan_blood_panel_vitamin_d_ng_ml"]["properties"] == {
        "panel": "blood_panel",
        "metric": "vitamin_d_ng_ml",
        "value": 28,
        "date": "2026-04-20",
    }
    assert nodes["LabResult:jordan_dexa_scan_lean_mass_kg"]["properties"] == {
        "panel": "dexa_scan",
        "metric": "lean_mass_kg",
        "value": 47.1,
        "date": "2026-03-30",
    }
    assert nodes["ChurnSignal:jordan_assessment_churn_risk"]["properties"]["risk_level"] == "elevated"
    assert nodes["SourceSpan:assessment_chat_03"]["properties"]["json_path"] == "$.chat_history[3]"


def test_assessment_import_command_writes_generated_artifacts(tmp_path) -> None:
    command = (
        "from pathlib import Path; "
        "from kg.assessment_import import write_assessment_import_artifacts; "
        "import json; "
        f"print(json.dumps(write_assessment_import_artifacts(Path({str(tmp_path)!r})), sort_keys=True))"
    )
    result = subprocess.run(
        [sys.executable, "-c", command],
        check=True,
        capture_output=True,
        text=True,
    )
    paths = json.loads(result.stdout)

    assert sorted(paths) == ["conformance_summary", "exercise_graph", "member_graph"]
    for path in paths.values():
        payload = json.loads(open(path, encoding="utf-8").read())
        assert isinstance(payload, dict)


def test_assessment_import_rejects_malformed_temp_exercise_fixture(tmp_path) -> None:
    exercises_path = tmp_path / "exercises.json"
    member_path = tmp_path / "member-context.json"
    exercises_path.write_text(json.dumps({"not": "a list"}), encoding="utf-8")
    member_path.write_text(json.dumps({"profile": {"name": "Synthetic"}}), encoding="utf-8")

    with pytest.raises(ValueError, match="exercises.json must contain a list"):
        build_assessment_import_artifacts(
            exercises_path=exercises_path,
            member_context_path=member_path,
        )


def test_assessment_import_rejects_malformed_temp_member_fixture(tmp_path) -> None:
    exercises_path = tmp_path / "exercises.json"
    member_path = tmp_path / "member-context.json"
    exercises_path.write_text(json.dumps([]), encoding="utf-8")
    member_path.write_text(json.dumps(["not", "an", "object"]), encoding="utf-8")

    with pytest.raises(ValueError, match="member-context.json must contain an object"):
        build_assessment_import_artifacts(
            exercises_path=exercises_path,
            member_context_path=member_path,
        )
