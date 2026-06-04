from __future__ import annotations

from kg.resolver import resolve_text


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


def test_resolves_equipment_terms() -> None:
    [kettlebell] = resolve_text("kettlebell")
    [barbell_exclusion] = resolve_text("no barbell")

    assert kettlebell.constraint_type == "Equipment"
    assert kettlebell.value == "kettlebell"
    assert kettlebell.negated is False
    assert barbell_exclusion.constraint_type == "Equipment"
    assert barbell_exclusion.value == "barbell"
    assert barbell_exclusion.hard is True
    assert barbell_exclusion.negated is True


def test_resolves_deadlift_family_exclusion() -> None:
    [constraint] = resolve_text("exclude deadlifts")

    assert constraint.constraint_type == "ExerciseFamily"
    assert constraint.value == "deadlift_family"
    assert constraint.hard is True
    assert constraint.negated is True


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
