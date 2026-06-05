from __future__ import annotations

import json
import subprocess
import sys

from kg.assessment_import import (
    SOURCE_SNAPSHOT_COMMIT,
    build_assessment_import_artifacts,
)
from kg.validation import validate_graph_seed


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
