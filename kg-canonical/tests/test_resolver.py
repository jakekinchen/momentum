from __future__ import annotations

from pathlib import Path

from kg.graph_store import load_local_graph
from kg.resolver import resolve_text


FULL_PRD_PROMPT = "Build a 50-minute lower-body session. Exclude deadlifts. Only DB and KB."


def test_resolves_knee_with_anatomy_closure_paths() -> None:
    [constraint] = resolve_text("knee")

    assert constraint.constraint_type == "BodyRegion"
    assert constraint.value == "knee"
    assert constraint.hard is False
    assert constraint.laterality is None
    assert "BodyRegion:left_knee -PART_OF-> BodyRegion:knee" in constraint.graph_paths
    assert "BodyRegion:patella -PART_OF-> BodyRegion:knee" in constraint.graph_paths
    assert all("MAPS_TO" not in path for path in constraint.graph_paths)


def test_resolves_left_knee_with_laterality() -> None:
    [constraint] = resolve_text("left knee")

    assert constraint.constraint_type == "BodyRegion"
    assert constraint.value == "left_knee"
    assert constraint.laterality == "left"
    assert constraint.graph_paths == ("BodyRegion:left_knee -PART_OF-> BodyRegion:knee",)


def test_resolves_bad_lower_back_as_safety_critical_body_region() -> None:
    [constraint] = resolve_text("bad lower back")

    assert constraint.constraint_type == "BodyRegion"
    assert constraint.value == "lower_back"
    assert constraint.hard is True
    assert constraint.verified is False
    assert constraint.safety_behavior == "block_if_safety_critical"
    assert constraint.graph_paths == (
        "BodyRegion:lumbar_spine -PART_OF-> BodyRegion:lower_back",
    )
    assert all("MAPS_TO" not in path for path in constraint.graph_paths)


def test_resolves_equipment_terms() -> None:
    [kettlebell] = resolve_text("kettlebell")
    [kb] = resolve_text("kb")
    [dumbbell] = resolve_text("dumbbell")
    [dumbbells] = resolve_text("dumbbells")
    [db] = resolve_text("db")
    [barbell_exclusion] = resolve_text("no barbell")

    assert kettlebell.constraint_type == "Equipment"
    assert kettlebell.value == "kettlebell"
    assert kettlebell.negated is False
    assert kb.constraint_type == "Equipment"
    assert kb.value == "kettlebell"
    assert dumbbell.constraint_type == "Equipment"
    assert dumbbell.value == "dumbbell"
    assert dumbbells.constraint_type == "Equipment"
    assert dumbbells.value == "dumbbell"
    assert db.constraint_type == "Equipment"
    assert db.value == "dumbbell"
    assert barbell_exclusion.constraint_type == "Equipment"
    assert barbell_exclusion.value == "barbell"
    assert barbell_exclusion.hard is True
    assert barbell_exclusion.negated is True


def test_resolves_only_db_kb_as_hard_allowed_equipment_subset() -> None:
    constraints = resolve_text("only dumbbells and kettlebell")

    assert [(constraint.constraint_type, constraint.value) for constraint in constraints] == [
        ("Equipment", "dumbbell"),
        ("Equipment", "kettlebell"),
    ]
    assert {f"Equipment:{constraint.value}" for constraint in constraints} == {
        "Equipment:dumbbell",
        "Equipment:kettlebell",
    }
    assert all(constraint.hard is True for constraint in constraints)
    assert all(constraint.negated is False for constraint in constraints)
    assert all(constraint.verified is False for constraint in constraints)
    assert all(constraint.safety_behavior == "allowed_equipment_only" for constraint in constraints)


def test_resolves_prd_db_kb_subset_with_terminal_punctuation() -> None:
    constraints = resolve_text("Only DB and KB.")

    assert [(constraint.constraint_type, constraint.value) for constraint in constraints] == [
        ("Equipment", "dumbbell"),
        ("Equipment", "kettlebell"),
    ]
    assert all(constraint.hard is True for constraint in constraints)
    assert all(constraint.source_text == "Only DB and KB." for constraint in constraints)
    assert all(constraint.safety_behavior == "allowed_equipment_only" for constraint in constraints)


def test_resolves_only_resistance_band_loop_alias() -> None:
    graph = load_local_graph(Path("graph/generated/assessment_exercise_kg.generated.json"))
    constraints = resolve_text("Build an arms routine. Only resistance band loop.", graph=graph)

    assert [(constraint.constraint_type, constraint.value) for constraint in constraints] == [
        ("Equipment", "resistance_band_loop"),
    ]
    assert all(constraint.hard is True for constraint in constraints)
    assert all(constraint.safety_behavior == "allowed_equipment_only" for constraint in constraints)
    assert all(constraint.confidence == 0.92 for constraint in constraints)
    assert all(constraint.resolution_method == "local_fuzzy_alias" for constraint in constraints)


def test_resolves_deadlift_family_exclusion() -> None:
    [constraint] = resolve_text("exclude deadlifts")

    assert constraint.constraint_type == "ExerciseFamily"
    assert constraint.value == "deadlift_family"
    assert constraint.hard is True
    assert constraint.negated is True


def test_resolves_full_prd_prompt_into_typed_constraints() -> None:
    constraints = resolve_text(FULL_PRD_PROMPT)

    assert [
        (
            constraint.constraint_type,
            constraint.value,
            constraint.hard,
            constraint.negated,
            constraint.safety_behavior,
            constraint.source_text,
        )
        for constraint in constraints
    ] == [
        ("ExerciseFamily", "deadlift_family", True, True, None, "Exclude deadlifts."),
        (
            "Equipment",
            "dumbbell",
            True,
            False,
            "allowed_equipment_only",
            "Only DB and KB.",
        ),
        (
            "Equipment",
            "kettlebell",
            True,
            False,
            "allowed_equipment_only",
            "Only DB and KB.",
        ),
    ]
    assert all(constraint.constraint_type != "UnresolvedConcept" for constraint in constraints)


def test_resolves_prd_alias_examples_from_local_graph() -> None:
    [pecs] = resolve_text("pecs")
    [squats] = resolve_text("squats")

    assert pecs.constraint_type == "MuscleGroup"
    assert pecs.value == "chest"
    assert pecs.hard is False
    assert pecs.verified is False
    assert squats.constraint_type == "MovementPattern"
    assert squats.value == "squat"
    assert squats.hard is False
    assert squats.verified is False


def test_unknown_or_ambiguous_terms_return_unresolved_constraint() -> None:
    [constraint] = resolve_text("press")

    assert constraint.constraint_type == "UnresolvedConcept"
    assert constraint.value == "press"
    assert constraint.hard is True
    assert constraint.resolution_status == "needs_review"
    assert constraint.safety_behavior == "ask_clarification"
    assert constraint.confidence == 0.0
    assert constraint.resolution_method == "unresolved"


def test_local_fuzzy_aliases_keep_safety_critical_blocks_hard() -> None:
    cases = [
        ("kne", "BodyRegion", "knee", False, False),
        ("no barbel", "Equipment", "barbell", True, True),
        ("dumbell", "Equipment", "dumbbell", False, False),
        ("kettle bell", "Equipment", "kettlebell", False, False),
        ("exclude dead lifts", "ExerciseFamily", "deadlift_family", True, True),
        ("low back", "BodyRegion", "lower_back", True, False),
        ("pectorals", "MuscleGroup", "chest", False, False),
    ]

    for text, constraint_type, value, hard, negated in cases:
        [constraint] = resolve_text(text)
        assert constraint.constraint_type == constraint_type
        assert constraint.value == value
        assert constraint.hard is hard
        assert constraint.negated is negated
        assert constraint.confidence == 0.92
        assert constraint.resolution_method == "local_fuzzy_alias"
