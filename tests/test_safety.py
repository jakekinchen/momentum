from __future__ import annotations

from kg.constraints import ResolvedConstraint
from kg.graph_store import GRAPH_DIR, load_json
from kg.resolver import resolve_text
from kg.safety import DecisionReceipt, evaluate_candidates, primary_severity


HOME_EQUIPMENT = {"Equipment:kettlebell", "Equipment:yoga_mat"}
DB_KB_EQUIPMENT = {"Equipment:dumbbell", "Equipment:kettlebell"}


def _receipt_for(exercise_id: str, **kwargs: object) -> DecisionReceipt:
    [receipt] = evaluate_candidates([exercise_id], **kwargs)
    return receipt


def _active_knee_restriction() -> ResolvedConstraint:
    [knee] = resolve_text("knee")
    return ResolvedConstraint(
        constraint_type=knee.constraint_type,
        value=knee.value,
        hard=True,
        source_text="active knee restriction",
        graph_paths=knee.graph_paths,
    )


def _active_lower_back_restriction() -> ResolvedConstraint:
    [lower_back] = resolve_text("bad lower back")
    return lower_back


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


def test_primary_severity_uses_prd_lattice() -> None:
    assert primary_severity(["PROMPT_EXCLUSION", "EQUIPMENT_HARD_BLOCK"]) == "EQUIPMENT_HARD_BLOCK"
    assert primary_severity(["SOFT_PENALTY", "MEDICAL_HARD_BLOCK"]) == "MEDICAL_HARD_BLOCK"


def test_missing_equipment_creates_hard_block_receipt() -> None:
    receipt = _receipt_for(
        "Exercise:barbell_bench_press",
        available_equipment=HOME_EQUIPMENT,
    )

    assert receipt.decision == "filtered"
    assert receipt.primary_severity == "EQUIPMENT_HARD_BLOCK"
    assert receipt.primary_reason_code == "MISSING_EQUIPMENT:barbell"
    assert receipt.reason_codes == ("MISSING_EQUIPMENT:barbell",)
    assert receipt.graph_paths == ("Exercise:barbell_bench_press -REQUIRES-> Equipment:barbell",)
    assert receipt.constraint_fingerprint
    assert receipt.graph_version == "fitgraph-kg-m5-validation-v0"
    assert receipt.ruleset_version == "ruleset-m2-safety-v0"
    assert receipt.ontology_lock_version == "ontology-lock-m0-unverified"


def test_only_db_kb_prompt_constraints_drive_hard_equipment_subset_filtering() -> None:
    constraints = resolve_text("only dumbbells and kettlebell")
    available_equipment = _equipment_ids_from_allowed_constraints(constraints)
    receipts = evaluate_candidates(
        [
            "Exercise:barbell_bench_press",
            "Exercise:dumbbell_floor_press",
            "Exercise:goblet_squat",
            "Exercise:glute_bridge",
        ],
        available_equipment=available_equipment,
        constraints=constraints,
    )
    by_id = {receipt.exercise_id: receipt for receipt in receipts}

    assert available_equipment == DB_KB_EQUIPMENT
    assert by_id["Exercise:barbell_bench_press"].decision == "filtered"
    assert by_id["Exercise:barbell_bench_press"].primary_severity == "EQUIPMENT_HARD_BLOCK"
    assert by_id["Exercise:barbell_bench_press"].primary_reason_code == "MISSING_EQUIPMENT:barbell"
    assert by_id["Exercise:barbell_bench_press"].graph_paths == (
        "Exercise:barbell_bench_press -REQUIRES-> Equipment:barbell",
    )
    assert by_id["Exercise:glute_bridge"].decision == "filtered"
    assert by_id["Exercise:glute_bridge"].primary_reason_code == "MISSING_EQUIPMENT:yoga_mat"
    assert by_id["Exercise:dumbbell_floor_press"].decision == "selected"
    assert by_id["Exercise:dumbbell_floor_press"].primary_reason_code == "PASSED_SAFETY"
    assert by_id["Exercise:goblet_squat"].decision == "selected"
    assert by_id["Exercise:goblet_squat"].primary_reason_code == "PASSED_SAFETY"


def test_deadlift_family_exclusion_uses_local_variant_edge() -> None:
    receipt = _receipt_for(
        "Exercise:kettlebell_deadlift",
        available_equipment=HOME_EQUIPMENT,
        constraints=resolve_text("exclude deadlifts"),
    )

    assert receipt.decision == "filtered"
    assert receipt.primary_severity == "PROMPT_EXCLUSION"
    assert receipt.primary_reason_code == "PROMPT_EXCLUDED_FAMILY:deadlift_family"
    assert receipt.reason_codes == ("PROMPT_EXCLUDED_FAMILY:deadlift_family",)
    assert receipt.graph_paths == (
        "Exercise:kettlebell_deadlift -VARIANT_OF-> ExerciseFamily:deadlift_family",
    )


def test_active_knee_restriction_blocks_loaded_knee_stress() -> None:
    receipt = _receipt_for(
        "Exercise:goblet_squat",
        available_equipment=HOME_EQUIPMENT,
        constraints=[_active_knee_restriction()],
    )

    assert receipt.decision == "filtered"
    assert receipt.primary_severity == "MEDICAL_HARD_BLOCK"
    assert receipt.primary_reason_code == "ACTIVE_KNEE_RESTRICTION"
    assert receipt.reason_codes == ("ACTIVE_KNEE_RESTRICTION",)
    assert "Exercise:goblet_squat -STRESSES-> BodyRegion:left_knee" in receipt.graph_paths
    assert "BodyRegion:left_knee -PART_OF-> BodyRegion:knee" in receipt.graph_paths
    assert "SafetyRule:avoid_loaded_knee_flexion -USES_CONCEPT-> BodyRegion:knee" in receipt.graph_paths


def test_safe_candidate_can_be_selected_under_knee_restriction() -> None:
    receipt = _receipt_for(
        "Exercise:glute_bridge",
        available_equipment=HOME_EQUIPMENT,
        constraints=[_active_knee_restriction()],
    )

    assert receipt.decision == "selected"
    assert receipt.primary_severity == "BOOST"
    assert receipt.reason_codes == ("PASSED_SAFETY",)
    assert receipt.primary_reason_code == "PASSED_SAFETY"
    assert receipt.graph_paths == ()


def test_bad_lower_back_restriction_blocks_loaded_lumbar_stress() -> None:
    receipt = _receipt_for(
        "Exercise:kettlebell_deadlift",
        available_equipment=HOME_EQUIPMENT,
        constraints=[_active_lower_back_restriction()],
    )

    assert receipt.decision == "filtered"
    assert receipt.primary_severity == "MEDICAL_HARD_BLOCK"
    assert receipt.primary_reason_code == "ACTIVE_LOWER_BACK_RESTRICTION"
    assert receipt.reason_codes == ("ACTIVE_LOWER_BACK_RESTRICTION",)
    assert "Exercise:kettlebell_deadlift -STRESSES-> BodyRegion:lumbar_spine" in receipt.graph_paths
    assert "BodyRegion:lumbar_spine -PART_OF-> BodyRegion:lower_back" in receipt.graph_paths
    assert (
        "SafetyRule:avoid_loaded_lumbar_stress -USES_CONCEPT-> BodyRegion:lower_back"
        in receipt.graph_paths
    )


def test_bad_lower_back_restriction_does_not_filter_all_available_exercises() -> None:
    receipts = evaluate_candidates(
        ["Exercise:kettlebell_deadlift", "Exercise:glute_bridge"],
        available_equipment=HOME_EQUIPMENT,
        constraints=[_active_lower_back_restriction()],
    )
    by_id = {receipt.exercise_id: receipt for receipt in receipts}

    assert by_id["Exercise:kettlebell_deadlift"].decision == "filtered"
    assert by_id["Exercise:glute_bridge"].decision == "selected"
    assert by_id["Exercise:glute_bridge"].primary_reason_code == "PASSED_SAFETY"
    assert by_id["Exercise:glute_bridge"].graph_paths == ()


def test_multiple_reasons_keep_secondary_and_choose_highest_severity() -> None:
    receipt = _receipt_for(
        "Exercise:goblet_squat",
        available_equipment={"Equipment:yoga_mat"},
        constraints=[_active_knee_restriction()],
    )

    assert receipt.decision == "filtered"
    assert receipt.primary_severity == "MEDICAL_HARD_BLOCK"
    assert receipt.primary_reason_code == "ACTIVE_KNEE_RESTRICTION"
    assert receipt.reason_codes == (
        "ACTIVE_KNEE_RESTRICTION",
        "MISSING_EQUIPMENT:kettlebell",
    )
    assert "Exercise:goblet_squat -REQUIRES-> Equipment:kettlebell" in receipt.graph_paths


def test_safety_rule_seed_preserves_no_llm_or_vector_policy() -> None:
    payload = load_json(GRAPH_DIR / "safety_rules.seed.json")

    assert payload["runtime_policy"]["deterministic_graph_traversal_decides_safety"] is True
    assert payload["runtime_policy"]["llm_decides_safety"] is False
    assert payload["runtime_policy"]["vector_search_for_safety_enforcement"] is False
