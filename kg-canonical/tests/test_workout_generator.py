from __future__ import annotations

import json
import subprocess
import sys

from kg.workout_generator import generate_workout


LOWER_BODY_DB_KB_PROMPT = "Build a 50-minute lower-body session. Exclude deadlifts. Only DB and KB."


def _lower_body_db_kb_result() -> dict[str, object]:
    return generate_workout(prompt=LOWER_BODY_DB_KB_PROMPT, minutes=50)


def _reason_codes(result: dict[str, object]) -> set[str]:
    return {
        code
        for receipt in result["filtered_exercises"]
        for code in receipt["reason_codes"]
    }


def test_assessment_workout_generator_preserves_graph_safety_contract() -> None:
    result = _lower_body_db_kb_result()

    assert result["graph_contract"] == {
        "eligibility_source": "deterministic_graph_traversal",
        "llm_decides_eligibility": False,
        "vector_search_enforces_safety": False,
    }
    assert result["available_equipment"] == ["Equipment:dumbbell", "Equipment:kettlebell"]
    assert all(
        constraint["constraint_type"] != "UnresolvedConcept"
        for constraint in result["resolved_constraints"]
    )
    assert any(
        constraint["constraint_type"] == "BodyRegion" and constraint["value"] == "left_knee"
        for constraint in result["resolved_constraints"]
    )
    assert result["selected_exercises"]
    assert result["workout"]["main"]
    selected_ids = {receipt["exercise_id"] for receipt in result["selected_exercises"]}
    assert all(record["alternative_exercise_id"] in selected_ids for record in result["alternatives"])


def test_lower_body_db_kb_prompt_selects_exact_safe_exercise_ids() -> None:
    result = _lower_body_db_kb_result()

    assert [receipt["exercise_id"] for receipt in result["selected_exercises"]] == [
        "Exercise:walking_toe_touches"
    ]
    assert result["workout"]["main"] == [
        {
            "exercise_id": "Exercise:walking_toe_touches",
            "name": "Walking Toe Touches",
            "sets": 3,
            "reps": "10-12",
            "rest_seconds": 75,
        }
    ]
    assert all(
        receipt["decision"] == "selected"
        and receipt["reason_codes"] == ("PASSED_SAFETY",)
        and receipt["primary_reason_code"] == "PASSED_SAFETY"
        for receipt in result["selected_exercises"]
    )


def test_lower_body_db_kb_prompt_pins_filtered_categories_and_deadlift_constraint() -> None:
    result = _lower_body_db_kb_result()

    resolved_constraints = {
        (
            constraint["constraint_type"],
            constraint["value"],
            constraint["hard"],
            constraint["negated"],
            constraint["safety_behavior"],
        )
        for constraint in result["resolved_constraints"]
    }
    assert (
        "ExerciseFamily",
        "deadlift_family",
        True,
        True,
        None,
    ) in resolved_constraints
    assert {
        ("Equipment", "dumbbell", True, False, "allowed_equipment_only"),
        ("Equipment", "kettlebell", True, False, "allowed_equipment_only"),
        ("BodyRegion", "left_knee", True, False, "block_if_safety_critical"),
    } <= resolved_constraints

    codes = _reason_codes(result)
    assert "MISSING_EQUIPMENT:barbell" in codes
    assert "ACTIVE_KNEE_RESTRICTION" in codes
    assert "ACTIVE_KNEE_HIGH_IMPACT_RESTRICTION" in codes
    assert not any(code.startswith("PROMPT_EXCLUDED_FAMILY:deadlift_family") for code in codes)
    assert sum(
        1
        for receipt in result["filtered_exercises"]
        if any(code.startswith("MISSING_EQUIPMENT:") for code in receipt["reason_codes"])
    ) == 18
    assert sum(
        1
        for receipt in result["filtered_exercises"]
        if any(code.startswith("ACTIVE_KNEE") for code in receipt["reason_codes"])
    ) == 13


def test_alternatives_point_to_selected_ids_and_never_self_reference() -> None:
    result = _lower_body_db_kb_result()
    selected_ids = {
        receipt["exercise_id"]
        for receipt in result["selected_exercises"]
    }
    filtered_ids = {
        receipt["exercise_id"]
        for receipt in result["filtered_exercises"]
    }

    assert result["alternatives"]
    for record in result["alternatives"]:
        assert record["alternative_exercise_id"] in selected_ids
        assert record["filtered_exercise_id"] in filtered_ids
        assert record["filtered_exercise_id"] == record["derived_from"]
        assert record["alternative_exercise_id"] != record["filtered_exercise_id"]


def test_unresolved_prompt_concepts_are_surfaced_without_blocking_safe_pool() -> None:
    result = generate_workout(
        prompt="Build a lower-body session. Moon boots.",
        minutes=30,
    )

    assert result["unresolved_concepts"] == [
        {
            "constraint_type": "UnresolvedConcept",
            "value": "moon boots",
            "hard": True,
            "source_text": "Moon boots.",
            "graph_paths": (),
            "verified": False,
            "negated": False,
            "laterality": None,
            "resolution_status": "needs_review",
            "safety_behavior": "ask_clarification",
        }
    ]
    assert result["selected_exercises"]
    assert result["graph_contract"]["eligibility_source"] == "deterministic_graph_traversal"


def test_missing_member_behavior_is_deterministic_and_does_not_crash() -> None:
    first = generate_workout(
        member_id="Member:missing",
        prompt="Build a chest session.",
        minutes=30,
    )
    second = generate_workout(
        member_id="Member:missing",
        prompt="Build a chest session.",
        minutes=30,
    )

    assert first == second
    assert first["member_id"] == "Member:missing"
    assert first["available_equipment"] == []
    assert first["selected_exercises"] == []
    assert [receipt["exercise_id"] for receipt in first["filtered_exercises"]] == [
        "Exercise:alternating_dumbbell_decline_bench_press",
        "Exercise:barbell_decline_bench_press",
        "Exercise:dumbbell_incline_chest_fly",
        "Exercise:dumbbell_neutral_grip_bench_press",
        "Exercise:push_up_to_knee_drive",
    ]
    assert all(
        receipt["primary_severity"] == "EQUIPMENT_HARD_BLOCK"
        for receipt in first["filtered_exercises"]
    )


def test_chest_and_default_prompt_branches_are_reachable() -> None:
    chest_result = generate_workout(prompt="Build a chest session.", minutes=30)
    default_result = generate_workout(prompt="Build a workout.", minutes=30)

    assert [receipt["exercise_id"] for receipt in chest_result["selected_exercises"]] == [
        "Exercise:dumbbell_neutral_grip_bench_press",
        "Exercise:push_up_to_knee_drive",
    ]
    assert chest_result["unresolved_concepts"][0]["value"] == "build a chest session"
    assert len(default_result["selected_exercises"]) > len(chest_result["selected_exercises"])
    assert default_result["selected_exercises"][0]["exercise_id"] == (
        "Exercise:alternating_dumbbell_overhead_press"
    )
    assert default_result["unresolved_concepts"][0]["value"] == "build a workout"


def test_workout_generator_command_outputs_json() -> None:
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "kg.workout_generator",
            "--prompt",
            "Lower-body workout for Jordan that avoids aggravating her left knee.",
            "--minutes",
            "50",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    payload = json.loads(result.stdout)

    assert payload["member_id"] == "Member:jordan"
    assert payload["prompt"].startswith("Lower-body workout")
    assert payload["decision_receipts"]
    assert payload["graph_contract"]["eligibility_source"] == "deterministic_graph_traversal"
