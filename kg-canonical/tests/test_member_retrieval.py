from __future__ import annotations

from kg.graph_store import GraphNode, LocalGraph
from kg.member_retrieval import (
    active_injuries,
    adherence_chart_series,
    adherence_trend,
    available_equipment,
    churn_risk,
    coach_brief,
    compare_last_4_weeks,
    copilot_chart_series,
    copilot_fact_cards,
    goals,
    last_4_weeks_chart_series,
    message_pattern,
    message_pattern_chart_series,
    quick_prompts,
    sleep_chart_series,
    sleep_this_week,
)


MEMBER_ID = "Member:jordan"


def test_quick_prompts_return_assessment_copilot_palette() -> None:
    prompts = quick_prompts(MEMBER_ID)

    assert tuple(prompt.key for prompt in prompts) == (
        "brief",
        "adherence_trend",
        "sleep_this_week",
        "churn_risk",
        "message_pattern",
        "compare_last_4_weeks",
    )
    assert tuple(prompt.label for prompt in prompts) == (
        "Show me the brief",
        "How is adherence trending?",
        "How did Jordan sleep this week?",
        "What is the churn risk?",
        "What is the message pattern?",
        "Compare the last 4 weeks",
    )


def test_available_equipment_returns_graph_backed_fact_card() -> None:
    [card] = available_equipment(MEMBER_ID)

    assert (
        card.claim
        == "Jordan Rivera has available equipment: Dumbbell, Kettlebell, Yoga Mat, "
        "Resistance Band - Loop, Flat Bench."
    )
    assert card.confidence == "deterministic"
    assert card.query == "member_retrieval.available_equipment"
    assert "EquipmentAvailability:jordan_home_equipment" in card.source_nodes
    assert "SourceSpan:jordan_equipment_assessment_fixture" in card.source_nodes


def test_active_injury_fact_card_is_source_backed() -> None:
    [card] = active_injuries(MEMBER_ID)

    assert (
        card.claim
        == "Jordan Rivera has an active left knee injury episode since 2026-05-10. "
        "Restrictions: Cleared for low-impact loading; Avoid deep knee flexion under load; "
        "Avoid plyometrics."
    )
    assert card.confidence == "deterministic"
    assert card.query == "member_retrieval.active_injuries"
    assert "InjuryEpisode:left_knee_issue_since_2026_05_10" in card.source_nodes
    assert "SourceSpan:jordan_injury_assessment_fixture" in card.source_nodes


def test_goals_return_imported_assessment_graph_data() -> None:
    cards = goals(MEMBER_ID)

    assert tuple(card.claim for card in cards) == (
        "Jordan Rivera's active goal is: Build lower-body strength.",
        "Jordan Rivera's active goal is: Return to pain-free squatting after left-knee flare-up.",
        "Jordan Rivera's active goal is: Average 7+ hours of sleep on weeknights.",
    )
    assert all(card.confidence == "deterministic" for card in cards)
    assert all(card.query == "member_retrieval.goals" for card in cards)
    assert "SourceSpan:jordan_goals_assessment_fixture" in cards[0].source_nodes


def test_adherence_trend_compares_four_graph_observations() -> None:
    [card] = adherence_trend(MEMBER_ID)

    assert (
        card.claim
        == "Adherence declined from 100% (4/4) on 2026-05-12 to 50% (2/4) "
        "on 2026-06-02 across 4 weekly observations."
    )
    assert card.confidence == "deterministic"
    assert card.query == "member_retrieval.adherence_trend"
    assert "AdherenceObservation:jordan_week_2026_05_12" in card.source_nodes
    assert "AdherenceObservation:jordan_week_2026_06_02" in card.source_nodes
    assert "SourceSpan:jordan_adherence_assessment_fixture" in card.source_nodes


def test_adherence_chart_series_is_generated_from_graph_facts() -> None:
    [series] = adherence_chart_series(MEMBER_ID)

    assert series.key == "adherence_trend"
    assert series.title == "Weekly adherence"
    assert series.unit == "percent"
    assert tuple(point.x for point in series.points) == (
        "2026-05-12",
        "2026-05-19",
        "2026-05-26",
        "2026-06-02",
    )
    assert tuple(point.y for point in series.points) == (100.0, 100.0, 75.0, 50.0)
    assert tuple(point.label for point in series.points) == (
        "100% (4/4)",
        "100% (4/4)",
        "75% (3/4)",
        "50% (2/4)",
    )
    assert "SourceSpan:jordan_adherence_assessment_fixture" in series.source_nodes


def test_sleep_this_week_returns_source_backed_biomarker_fact_card() -> None:
    [card] = sleep_this_week(MEMBER_ID)

    assert card.claim == "Jordan Rivera averaged 6.3 hours of sleep over 7 nights ending 2026-06-04."
    assert card.confidence == "deterministic"
    assert card.query == "member_retrieval.sleep_this_week"
    assert "BiomarkerObservation:jordan_sleep_week_2026_06_04" in card.source_nodes
    assert "SourceSpan:jordan_sleep_assessment_fixture" in card.source_nodes


def test_sleep_chart_series_uses_all_seven_sleep_values() -> None:
    [series] = sleep_chart_series(MEMBER_ID)

    assert series.key == "sleep_this_week"
    assert series.title == "Sleep this week"
    assert series.unit == "hours"
    assert tuple(point.x for point in series.points) == (
        "2026-05-29",
        "2026-05-30",
        "2026-05-31",
        "2026-06-01",
        "2026-06-02",
        "2026-06-03",
        "2026-06-04",
    )
    assert tuple(point.y for point in series.points) == (6.1, 5.4, 7.2, 6.0, 5.1, 7.8, 6.3)
    assert "SourceSpan:jordan_sleep_assessment_fixture" in series.source_nodes


def test_churn_risk_returns_explicit_graph_signal_without_model_scoring() -> None:
    [card] = churn_risk(MEMBER_ID)

    assert (
        card.claim
        == "Jordan Rivera has elevated churn risk on 2026-06-04 from 3 deterministic graph reasons: "
        "Weekly adherence fell from 100% to 50% over 2 weeks; "
        "One skipped session with a fatigue/work explanation; "
        "Login frequency down vs. prior month."
    )
    assert card.confidence == "deterministic"
    assert card.query == "member_retrieval.churn_risk"
    assert "ChurnSignal:jordan_elevated_adherence_fatigue_2026_06_04" in card.source_nodes
    assert "SourceSpan:jordan_coach_brief_assessment_fixture" in card.source_nodes


def test_churn_risk_chart_series_uses_deterministic_reason_indicators() -> None:
    [series] = copilot_chart_series(MEMBER_ID, "churn_risk")

    assert series.key == "churn_risk"
    assert series.title == "Churn risk factors"
    assert series.unit == "present"
    assert tuple(point.x for point in series.points) == (
        "Weekly adherence fell from 100% to 50% over 2 weeks",
        "One skipped session with a fatigue/work explanation",
        "Login frequency down vs. prior month",
    )
    assert tuple(point.y for point in series.points) == (1.0, 1.0, 1.0)


def test_coach_brief_returns_source_backed_brief_text() -> None:
    [card] = coach_brief(MEMBER_ID)

    assert (
        card.claim
        == "Coach brief for Jordan Rivera on 2026-06-04: Congratulate Jordan on completing "
        "yesterday's lower-body session, the first pain-free squat work since the knee "
        "flare-up. Then review elevated churn risk because adherence dropped from 100% "
        "to 50% over the last two weeks."
    )
    assert card.confidence == "deterministic"
    assert card.query == "member_retrieval.coach_brief"
    assert "CoachBrief:jordan_morning_2026_06_04" in card.source_nodes
    assert "SourceSpan:jordan_coach_brief_assessment_fixture" in card.source_nodes


def test_message_pattern_fact_card_summarizes_source_backed_chat_history() -> None:
    [card] = message_pattern(MEMBER_ID)

    assert (
        card.claim
        == "Message pattern for Jordan Rivera: 4 messages from 2026-05-22 to 2026-06-03; "
        "coach sent 1, member sent 3. Latest member message: Knocked out the lower body "
        "session! Knee felt okay with the box squats."
    )
    assert card.confidence == "deterministic"
    assert card.query == "member_retrieval.message_pattern"
    assert "Message:jordan_2026_05_22_0750_member" in card.source_nodes
    assert "Message:jordan_2026_06_03_1905_coach" in card.source_nodes
    assert "SourceSpan:jordan_chat_history_assessment_fixture" in card.source_nodes


def test_message_pattern_chart_series_counts_messages_by_sender_and_date() -> None:
    coach_series, member_series = message_pattern_chart_series(MEMBER_ID)

    assert coach_series.key == "message_pattern_coach"
    assert tuple((point.x, point.y, point.label) for point in coach_series.points) == (
        ("2026-06-03", 1.0, "1 coach message"),
    )
    assert member_series.key == "message_pattern_member"
    assert tuple((point.x, point.y, point.label) for point in member_series.points) == (
        ("2026-05-22", 1.0, "1 member message"),
        ("2026-05-30", 1.0, "1 member message"),
        ("2026-06-03", 1.0, "1 member message"),
    )


def test_compare_last_4_weeks_fact_card_uses_adherence_and_workouts() -> None:
    [card] = compare_last_4_weeks(MEMBER_ID)

    assert (
        card.claim
        == "Last 4 weeks for Jordan Rivera: weekly adherence was 100%, 100%, 75%, "
        "and 50%; logged workouts completed 3/4 with average completed-session RPE 6.3."
    )
    assert card.confidence == "deterministic"
    assert card.query == "member_retrieval.compare_last_4_weeks"
    assert "AdherenceObservation:jordan_week_2026_05_12" in card.source_nodes
    assert "WorkoutSession:jordan_2026_06_03_lower_body_bands_db" in card.source_nodes
    assert "SourceSpan:jordan_workout_history_assessment_fixture" in card.source_nodes


def test_last_4_weeks_chart_series_returns_adherence_and_workout_series() -> None:
    adherence_series, workout_series = last_4_weeks_chart_series(MEMBER_ID)

    assert adherence_series.key == "compare_last_4_weeks_adherence"
    assert tuple(point.y for point in adherence_series.points) == (100.0, 100.0, 75.0, 50.0)
    assert workout_series.key == "compare_last_4_weeks_workouts"
    assert tuple((point.x, point.y, point.label) for point in workout_series.points) == (
        ("2026-05-27", 1.0, "completed"),
        ("2026-05-29", 0.0, "missed"),
        ("2026-06-01", 1.0, "completed"),
        ("2026-06-03", 1.0, "completed"),
    )


def test_copilot_prompt_router_returns_fact_cards_and_chart_series() -> None:
    [brief_card] = copilot_fact_cards(MEMBER_ID, "show brief")
    [sleep_series] = copilot_chart_series(MEMBER_ID, "sleep")

    assert brief_card.query == "member_retrieval.coach_brief"
    assert brief_card.claim.startswith("Coach brief for Jordan Rivera")
    assert sleep_series.query == "member_retrieval.sleep_chart_series"
    assert sleep_series.key == "sleep_this_week"


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

    [message_card] = message_pattern("Member:no_data", graph=graph)
    assert message_card.claim == "The graph has no supporting fact for Member:no_data."
    assert message_card.confidence == "deterministic"
    assert message_card.query == "member_retrieval.message_pattern"
    assert message_card.source_nodes == ()

    [compare_card] = compare_last_4_weeks("Member:no_data", graph=graph)
    assert compare_card.claim == "The graph has no supporting fact for Member:no_data."
    assert compare_card.confidence == "deterministic"
    assert compare_card.query == "member_retrieval.compare_last_4_weeks"
    assert compare_card.source_nodes == ()

    assert copilot_chart_series("Member:no_data", "message_pattern", graph=graph) == []


def test_missing_member_returns_no_supporting_fact_card() -> None:
    [card] = available_equipment("Member:unknown")

    assert card.claim == "The graph has no supporting fact for Member:unknown."
    assert card.confidence == "deterministic"
    assert card.query == "member_retrieval.available_equipment"
    assert card.source_nodes == ()
    assert quick_prompts("Member:unknown") == ()


def test_unknown_prompt_returns_deterministic_no_supporting_fact_card() -> None:
    [card] = copilot_fact_cards(MEMBER_ID, "unmodeled prompt")

    assert card.claim == "The graph has no supporting fact for Member:jordan."
    assert card.confidence == "deterministic"
    assert card.query == "member_retrieval.unmodeled_prompt"
    assert card.source_nodes == ()
