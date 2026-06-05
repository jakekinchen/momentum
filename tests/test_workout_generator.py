from __future__ import annotations

import json
import subprocess
import sys

from kg.workout_generator import generate_workout


def test_assessment_workout_generator_preserves_graph_safety_contract() -> None:
    result = generate_workout(
        prompt="Build a 50-minute lower-body session. Exclude deadlifts. Only DB and KB.",
        minutes=50,
    )

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
    assert any(
        "MISSING_EQUIPMENT:barbell" in receipt["reason_codes"]
        for receipt in result["filtered_exercises"]
    )
    assert any(
        "ACTIVE_KNEE" in receipt["primary_reason_code"]
        for receipt in result["filtered_exercises"]
    )
    selected_ids = {receipt["exercise_id"] for receipt in result["selected_exercises"]}
    assert all(record["alternative_exercise_id"] in selected_ids for record in result["alternatives"])


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
