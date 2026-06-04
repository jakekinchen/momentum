from __future__ import annotations

from kg.alternatives import build_workout_candidates, select_alternatives
from kg.constraints import ResolvedConstraint
from kg.resolver import resolve_text
from kg.safety import DecisionReceipt, evaluate_candidates


HOME_EQUIPMENT = {"Equipment:kettlebell", "Equipment:yoga_mat"}
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
