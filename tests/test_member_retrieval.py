from __future__ import annotations

from kg.member_retrieval import active_injuries, adherence_trend, available_equipment, goals


MEMBER_ID = "Member:jordan"


def test_available_equipment_returns_graph_backed_fact_card() -> None:
    [card] = available_equipment(MEMBER_ID)

    assert card.claim == "Jordan has available equipment: kettlebell, yoga mat."
    assert card.confidence == "deterministic"
    assert card.query == "member_retrieval.available_equipment"
    assert "EquipmentAvailability:jordan_home_equipment" in card.source_nodes
    assert "SourceSpan:jordan_intake_2026_06_04" in card.source_nodes


def test_active_injury_fact_card_is_source_backed() -> None:
    [card] = active_injuries(MEMBER_ID)

    assert card.claim == "Jordan has an active left knee injury episode since 2026-05-10."
    assert card.confidence == "deterministic"
    assert card.query == "member_retrieval.active_injuries"
    assert "InjuryEpisode:left_knee_issue_since_2026_05_10" in card.source_nodes
    assert "SourceSpan:jordan_intake_2026_06_04" in card.source_nodes


def test_goals_return_from_graph_data() -> None:
    [card] = goals(MEMBER_ID)

    assert (
        card.claim
        == "Jordan's active goal is: Build lower-body strength without aggravating left knee."
    )
    assert card.confidence == "deterministic"
    assert card.query == "member_retrieval.goals"
    assert "Goal:jordan_lower_body_strength" in card.source_nodes


def test_adherence_trend_compares_two_graph_observations() -> None:
    [card] = adherence_trend(MEMBER_ID)

    assert (
        card.claim
        == "Adherence declined from 100% (4/4) on 2026-05-19 to 50% (2/4) on 2026-06-02."
    )
    assert card.confidence == "deterministic"
    assert card.query == "member_retrieval.adherence_trend"
    assert card.source_nodes == (
        "AdherenceObservation:jordan_week_2026_05_19",
        "AdherenceObservation:jordan_week_2026_06_02",
    )


def test_missing_member_returns_no_supporting_fact_card() -> None:
    [card] = available_equipment("Member:unknown")

    assert card.claim == "The graph has no supporting fact for Member:unknown."
    assert card.confidence == "deterministic"
    assert card.query == "member_retrieval.available_equipment"
    assert card.source_nodes == ()
