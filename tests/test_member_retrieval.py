from __future__ import annotations

from kg.graph_store import GraphNode, LocalGraph
from kg.member_retrieval import (
    active_injuries,
    adherence_trend,
    available_equipment,
    churn_risk,
    coach_brief,
    goals,
    sleep_this_week,
)


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


def test_sleep_this_week_returns_source_backed_biomarker_fact_card() -> None:
    [card] = sleep_this_week(MEMBER_ID)

    assert card.claim == "Jordan averaged 6.3 hours of sleep over 7 nights ending 2026-06-04."
    assert card.confidence == "deterministic"
    assert card.query == "member_retrieval.sleep_this_week"
    assert "BiomarkerObservation:jordan_sleep_week_2026_06_04" in card.source_nodes
    assert "SourceSpan:jordan_copilot_snapshot_2026_06_04" in card.source_nodes


def test_churn_risk_returns_explicit_graph_signal_without_model_scoring() -> None:
    [card] = churn_risk(MEMBER_ID)

    assert (
        card.claim
        == "Jordan has elevated churn risk on 2026-06-04: "
        "Weekly adherence fell from 100% to 50% over 2 weeks; "
        "One skipped session with a fatigue/work explanation; "
        "Login frequency down vs. prior month."
    )
    assert card.confidence == "deterministic"
    assert card.query == "member_retrieval.churn_risk"
    assert "ChurnSignal:jordan_elevated_adherence_fatigue_2026_06_04" in card.source_nodes
    assert "SourceSpan:jordan_copilot_snapshot_2026_06_04" in card.source_nodes


def test_coach_brief_returns_source_backed_brief_text() -> None:
    [card] = coach_brief(MEMBER_ID)

    assert (
        card.claim
        == "Coach brief for Jordan on 2026-06-04: Congratulate Jordan on completing "
        "yesterday's lower-body session, the first pain-free squat work since the knee "
        "flare-up. Then review elevated churn risk because adherence dropped from 100% "
        "to 50% over the last two weeks."
    )
    assert card.confidence == "deterministic"
    assert card.query == "member_retrieval.coach_brief"
    assert "CoachBrief:jordan_morning_2026_06_04" in card.source_nodes
    assert "SourceSpan:jordan_copilot_snapshot_2026_06_04" in card.source_nodes


def test_missing_copilot_data_returns_no_supporting_fact_card() -> None:
    graph = LocalGraph(
        nodes={
            "Member:no_data": GraphNode(
                id="Member:no_data",
                type="Member",
                label="No Data",
            )
        },
        edges=(),
    )

    [sleep_card] = sleep_this_week("Member:no_data", graph=graph)
    assert sleep_card.claim == "The graph has no supporting fact for Member:no_data."
    assert sleep_card.confidence == "deterministic"
    assert sleep_card.query == "member_retrieval.sleep_this_week"
    assert sleep_card.source_nodes == ()

    [card] = churn_risk("Member:no_data", graph=graph)
    assert card.claim == "The graph has no supporting fact for Member:no_data."
    assert card.confidence == "deterministic"
    assert card.query == "member_retrieval.churn_risk"
    assert card.source_nodes == ()

    [brief_card] = coach_brief("Member:no_data", graph=graph)
    assert brief_card.claim == "The graph has no supporting fact for Member:no_data."
    assert brief_card.confidence == "deterministic"
    assert brief_card.query == "member_retrieval.coach_brief"
    assert brief_card.source_nodes == ()


def test_missing_member_returns_no_supporting_fact_card() -> None:
    [card] = available_equipment("Member:unknown")

    assert card.claim == "The graph has no supporting fact for Member:unknown."
    assert card.confidence == "deterministic"
    assert card.query == "member_retrieval.available_equipment"
    assert card.source_nodes == ()
