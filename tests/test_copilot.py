from __future__ import annotations

import json
import subprocess
import sys

from kg.copilot import answer_copilot


def test_copilot_answers_quick_prompts_with_fact_cards_and_charts() -> None:
    brief = answer_copilot(question="Show me the brief")
    adherence = answer_copilot(question="How's adherence trending?")
    sleep = answer_copilot(question="Sleep this week")
    churn = answer_copilot(question="Check churn risk")
    messages = answer_copilot(question="Show message pattern")

    assert brief["fact_cards"][0]["confidence"] == "deterministic"
    assert "Coach brief" in brief["fact_cards"][0]["claim"]
    assert adherence["chart_series"][0]["key"] == "adherence_trend"
    assert adherence["chart_series"][0]["points"][-1]["y"] == 50.0
    assert sleep["chart_series"][0]["key"] == "sleep_this_week"
    assert len(sleep["chart_series"][0]["points"]) == 7
    assert churn["fact_cards"][0]["source_nodes"]
    assert churn["fact_cards"][0]["claim"].lower().find("elevated") >= 0
    assert {series["key"] for series in messages["chart_series"]} == {
        "message_pattern_coach",
        "message_pattern_member",
    }
    assert messages["retrieved_messages"]
    assert all(card["confidence"] == "deterministic" for card in brief["fact_cards"])


def test_copilot_last_four_weeks_and_no_supporting_fact_behavior() -> None:
    comparison = answer_copilot(question="Compare last 4 weeks")
    missing = answer_copilot(member_id="Member:missing", question="Show me the brief")

    assert {series["key"] for series in comparison["chart_series"]} == {
        "compare_last_4_weeks_adherence",
        "compare_last_4_weeks_workouts",
    }
    assert comparison["answer_constraints"]["invent_member_data"] is False
    assert missing["fact_cards"][0]["claim"] == "The graph has no supporting fact for Member:missing."


def test_copilot_command_outputs_json() -> None:
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "kg.copilot",
            "--question",
            "Sleep this week",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    payload = json.loads(result.stdout)

    assert payload["question"] == "Sleep this week"
    assert payload["chart_series"][0]["key"] == "sleep_this_week"
    assert payload["answer_constraints"]["summarize_only_fact_cards"] is True
