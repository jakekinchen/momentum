from __future__ import annotations

from kg.alternatives import build_workout_candidates, select_alternatives
from kg.constraints import ResolvedConstraint
from kg.resolver import resolve_text
from kg.safety import DecisionReceipt, evaluate_candidates


HOME_EQUIPMENT = {"Equipment:kettlebell", "Equipment:yoga_mat"}
DB_KB_EQUIPMENT = {"Equipment:dumbbell", "Equipment:kettlebell"}
FULL_PRD_PROMPT = "Build a 50-minute lower-body session. Exclude deadlifts. Only DB and KB."
LOWER_BODY_CANDIDATES = (
    "Exercise:barbell_back_squat",
    "Exercise:goblet_squat",
    "Exercise:kettlebell_deadlift",
    "Exercise:glute_bridge",
    "Exercise:jump_squat",
)
CANDIDATES = (
    "Exercise:goblet_squat",
    "Exercise:kettlebell_deadlift",
    "Exercise:barbell_bench_press",
    "Exercise:glute_bridge",
)


def _active_knee_restriction() -> ResolvedConstraint:
    [knee] = resolve_text("knee")
    return ResolvedConstraint(
        constraint_type=knee.constraint_type,
        value=knee.value,
        hard=True,
        source_text="active knee restriction",
        graph_paths=knee.graph_paths,
    )


def _equipment_ids_from_allowed_constraints(
    constraints: list[ResolvedConstraint],
) -> set[str]:
    return {
        f"Equipment:{constraint.value}"
        for constraint in constraints
        if constraint.constraint_type == "Equipment"
        and constraint.hard
        and constraint.safety_behavior == "allowed_equipment_only"
    }


def _safety_receipts() -> list[DecisionReceipt]:
    return evaluate_candidates(
        CANDIDATES,
        available_equipment=HOME_EQUIPMENT,
        constraints=[_active_knee_restriction(), *resolve_text("exclude deadlifts")],
    )


def test_alternatives_are_selected_from_selected_receipts_only() -> None:
    receipts = _safety_receipts()
    selected_ids = {receipt.exercise_id for receipt in receipts if receipt.decision == "selected"}
    alternatives = select_alternatives(receipts, available_equipment=HOME_EQUIPMENT)

    assert selected_ids == {"Exercise:glute_bridge"}
    assert alternatives
    assert {record.alternative_exercise_id for record in alternatives} == selected_ids
    assert all(record.alternative_exercise_id != record.filtered_exercise_id for record in alternatives)


def test_glute_bridge_is_alternative_for_filtered_knee_stressing_candidate() -> None:
    alternatives = select_alternatives(_safety_receipts(), available_equipment=HOME_EQUIPMENT)
    [goblet_record] = [
        record for record in alternatives if record.filtered_exercise_id == "Exercise:goblet_squat"
    ]

    assert goblet_record.alternative_exercise_id == "Exercise:glute_bridge"
    assert goblet_record.derived_from == "Exercise:goblet_squat"
    assert goblet_record.score > 0
    assert goblet_record.score_components["target_overlap"] > 0
    assert goblet_record.score_components["equipment_preference"] == 1.0
    assert "Exercise:goblet_squat -TARGETS-> MuscleGroup:glutes" in goblet_record.graph_paths
    assert "Exercise:glute_bridge -TARGETS-> MuscleGroup:glutes" in goblet_record.graph_paths
    assert "Exercise:glute_bridge -REQUIRES-> Equipment:yoga_mat" in goblet_record.graph_paths
    assert "Exercise:glute_bridge -STRESSES-> BodyRegion:hip" in goblet_record.graph_paths


def test_no_alternative_is_returned_when_safe_pool_is_empty() -> None:
    receipts = evaluate_candidates(
        CANDIDATES,
        available_equipment=set(),
        constraints=[_active_knee_restriction(), *resolve_text("exclude deadlifts")],
    )

    assert all(receipt.decision == "filtered" for receipt in receipts)
    assert select_alternatives(receipts, available_equipment=set()) == []


def test_alternative_output_ordering_is_deterministic() -> None:
    receipts = _safety_receipts()

    first = select_alternatives(receipts, available_equipment=HOME_EQUIPMENT)
    second = select_alternatives(receipts, available_equipment=HOME_EQUIPMENT)

    assert first == second
    assert [record.filtered_exercise_id for record in first] == [
        "Exercise:barbell_bench_press",
        "Exercise:goblet_squat",
        "Exercise:kettlebell_deadlift",
    ]


def test_workout_candidate_contract_returns_receipts_and_alternatives() -> None:
    receipts = _safety_receipts()
    result = build_workout_candidates(receipts, available_equipment=HOME_EQUIPMENT)

    assert [receipt.exercise_id for receipt in result.selected_receipts] == ["Exercise:glute_bridge"]
    assert {receipt.exercise_id for receipt in result.filtered_receipts} == {
        "Exercise:goblet_squat",
        "Exercise:kettlebell_deadlift",
        "Exercise:barbell_bench_press",
    }
    assert len(result.alternatives) == len(result.filtered_receipts)
    assert {record.alternative_exercise_id for record in result.alternatives} == {
        "Exercise:glute_bridge"
    }


def test_db_kb_workout_candidates_use_only_selected_safe_pool_for_alternatives() -> None:
    constraints = resolve_text("only dumbbells and kettlebell")
    available_equipment = _equipment_ids_from_allowed_constraints(constraints)
    receipts = evaluate_candidates(
        [
            "Exercise:barbell_bench_press",
            "Exercise:dumbbell_floor_press",
            "Exercise:kettlebell_deadlift",
            "Exercise:glute_bridge",
        ],
        available_equipment=available_equipment,
        constraints=constraints,
    )
    result = build_workout_candidates(receipts, available_equipment=available_equipment)
    selected_ids = {receipt.exercise_id for receipt in result.selected_receipts}
    alternatives_by_filtered = {
        record.filtered_exercise_id: record for record in result.alternatives
    }

    assert available_equipment == DB_KB_EQUIPMENT
    assert selected_ids == {
        "Exercise:dumbbell_floor_press",
        "Exercise:kettlebell_deadlift",
    }
    assert {receipt.exercise_id for receipt in result.filtered_receipts} == {
        "Exercise:barbell_bench_press",
        "Exercise:glute_bridge",
    }
    assert all(record.alternative_exercise_id in selected_ids for record in result.alternatives)
    assert (
        alternatives_by_filtered["Exercise:barbell_bench_press"].alternative_exercise_id
        == "Exercise:dumbbell_floor_press"
    )
    assert (
        "Exercise:dumbbell_floor_press -REQUIRES-> Equipment:dumbbell"
        in alternatives_by_filtered["Exercise:barbell_bench_press"].graph_paths
    )


def test_full_prd_prompt_workout_candidates_use_selected_db_kb_pool_for_alternatives() -> None:
    constraints = resolve_text(FULL_PRD_PROMPT)
    available_equipment = _equipment_ids_from_allowed_constraints(constraints)
    receipts = evaluate_candidates(
        LOWER_BODY_CANDIDATES,
        available_equipment=available_equipment,
        constraints=constraints,
    )
    result = build_workout_candidates(receipts, available_equipment=available_equipment)
    selected_ids = {receipt.exercise_id for receipt in result.selected_receipts}
    alternatives_by_filtered = {
        record.filtered_exercise_id: record for record in result.alternatives
    }

    assert available_equipment == DB_KB_EQUIPMENT
    assert selected_ids == {"Exercise:goblet_squat"}
    assert {receipt.exercise_id for receipt in result.filtered_receipts} == {
        "Exercise:barbell_back_squat",
        "Exercise:kettlebell_deadlift",
        "Exercise:glute_bridge",
        "Exercise:jump_squat",
    }
    assert all(record.alternative_exercise_id in selected_ids for record in result.alternatives)
    assert {record.alternative_exercise_id for record in result.alternatives} == {
        "Exercise:goblet_squat",
    }
    assert (
        alternatives_by_filtered["Exercise:barbell_back_squat"].alternative_exercise_id
        == "Exercise:goblet_squat"
    )
    assert (
        "Exercise:barbell_back_squat -HAS_PATTERN-> MovementPattern:squat"
        in alternatives_by_filtered["Exercise:barbell_back_squat"].graph_paths
    )
    assert (
        "Exercise:goblet_squat -HAS_PATTERN-> MovementPattern:squat"
        in alternatives_by_filtered["Exercise:barbell_back_squat"].graph_paths
    )
    assert (
        "Exercise:goblet_squat -REQUIRES-> Equipment:kettlebell"
        in alternatives_by_filtered["Exercise:barbell_back_squat"].graph_paths
    )
    assert all(
        record.alternative_exercise_id != record.filtered_exercise_id
        for record in result.alternatives
    )
