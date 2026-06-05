from __future__ import annotations

import json
import subprocess
import sys
from typing import Any

import pytest
from kg.copilot import answer_copilot


EXPECTED_ANSWER_CONSTRAINTS = {
    "summarize_only_fact_cards": True,
    "invent_member_data": False,
    "llm_decides_eligibility": False,
    "vector_search_enforces_safety": False,
}


QUICK_PROMPT_CASES = {
    "brief": {
        "question": "Show me the brief",
        "fact_query": "member_retrieval.coach_brief",
        "claim_contains": ("Coach brief", "Jordan Rivera"),
        "chart_points": {},
        "source_backed": True,
    },
    "adherence_trend": {
        "question": "How's adherence trending?",
        "fact_query": "member_retrieval.adherence_trend",
        "claim_contains": ("Adherence declined", "50%"),
        "chart_points": {"adherence_trend": 4},
        "source_backed": True,
    },
    "sleep_this_week": {
        "question": "Sleep this week",
        "fact_query": "member_retrieval.sleep_this_week",
        "claim_contains": ("averaged 6.3 hours", "7 nights"),
        "chart_points": {"sleep_this_week": 7},
        "source_backed": True,
    },
    "churn_risk": {
        "question": "Check churn risk",
        "fact_query": "member_retrieval.churn_risk",
        "claim_contains": ("elevated churn risk", "deterministic graph reasons"),
        "chart_points": {"churn_risk": 3},
        "source_backed": True,
    },
    "message_pattern": {
        "question": "Show message pattern",
        "fact_query": "member_retrieval.message_pattern",
        "claim_contains": ("Message pattern", "Latest member message"),
        "chart_points": {
            "message_pattern_coach": 1,
            "message_pattern_member": 3,
        },
        "source_backed": True,
    },
    "compare_last_4_weeks": {
        "question": "Compare last 4 weeks",
        "fact_query": "member_retrieval.compare_last_4_weeks",
        "claim_contains": ("Last 4 weeks", "logged workouts completed 3/4"),
        "chart_points": {
            "compare_last_4_weeks_adherence": 4,
            "compare_last_4_weeks_workouts": 4,
        },
        "source_backed": True,
    },
    "available_equipment": {
        "question": "What equipment is available?",
        "fact_query": "member_retrieval.available_equipment",
        "claim_contains": ("available equipment", "Dumbbell"),
        "chart_points": {},
        "source_backed": True,
    },
    "active_injuries": {
        "question": "Any active injuries?",
        "fact_query": "member_retrieval.active_injuries",
        "claim_contains": ("active left knee injury", "Avoid plyometrics"),
        "chart_points": {},
        "source_backed": True,
    },
    "unknown": {
        "question": "Tell me something poetic",
        "fact_query": "copilot.unknown",
        "claim_contains": ("no supporting fact for Member:jordan",),
        "chart_points": {},
        "source_backed": False,
    },
}


def _assert_answer_constraints(payload: dict[str, Any]) -> None:
    assert payload["answer_constraints"] == EXPECTED_ANSWER_CONSTRAINTS
    _assert_no_vector_or_llm_flag_enabled(payload)


def _assert_no_vector_or_llm_flag_enabled(value: Any) -> None:
    if isinstance(value, dict):
        for key, item in value.items():
            lowered_key = str(key).lower()
            if isinstance(item, bool) and ("llm" in lowered_key or "vector" in lowered_key):
                assert item is False
            _assert_no_vector_or_llm_flag_enabled(item)
    elif isinstance(value, list | tuple):
        for item in value:
            _assert_no_vector_or_llm_flag_enabled(item)


def _assert_fact_card_contract(card: dict[str, Any]) -> None:
    assert card["confidence"] == "deterministic"
    assert isinstance(card["claim"], str)
    assert card["claim"]
    assert isinstance(card["query"], str)
    assert card["query"]
    assert isinstance(card["source_nodes"], list | tuple)


def _assert_chart_series_contract(series: dict[str, Any]) -> None:
    assert isinstance(series["key"], str)
    assert isinstance(series["title"], str)
    assert isinstance(series["unit"], str)
    assert isinstance(series["query"], str)
    assert series["source_nodes"]
    for point in series["points"]:
        assert isinstance(point["x"], str)
        assert isinstance(point["y"], int | float)
        assert not isinstance(point["y"], bool)
        assert isinstance(point["label"], str)
        assert point["source_nodes"]


def _assert_payload_contract(payload: dict[str, Any]) -> None:
    assert payload["member_id"]
    assert payload["question"]
    assert payload["quick_prompt_key"]
    assert payload["fact_cards"]
    _assert_answer_constraints(payload)
    for card in payload["fact_cards"]:
        _assert_fact_card_contract(card)
    for series in payload["chart_series"]:
        _assert_chart_series_contract(series)
    for message in payload["retrieved_messages"]:
        _assert_fact_card_contract(message)
        assert message["source_nodes"]


@pytest.mark.parametrize("expected_key", tuple(QUICK_PROMPT_CASES))
def test_copilot_routes_every_quick_prompt_to_deterministic_contract(
    expected_key: str,
) -> None:
    case = QUICK_PROMPT_CASES[expected_key]
    payload = answer_copilot(question=str(case["question"]))

    _assert_payload_contract(payload)
    assert payload["quick_prompt_key"] == expected_key
    assert [card["query"] for card in payload["fact_cards"]] == [case["fact_query"]]
    for expected_text in case["claim_contains"]:
        assert expected_text in payload["fact_cards"][0]["claim"]
    assert {
        series["key"]: len(series["points"]) for series in payload["chart_series"]
    } == case["chart_points"]
    if case["source_backed"]:
        assert payload["fact_cards"][0]["source_nodes"]
    else:
        assert payload["fact_cards"][0]["source_nodes"] == ()


def test_copilot_retrieves_only_source_backed_messages_for_known_member() -> None:
    payload = answer_copilot(question="Show message pattern")

    _assert_payload_contract(payload)
    assert payload["retrieved_messages"]
    assert [message["query"] for message in payload["retrieved_messages"]] == [
        "member_retrieval.message_pattern"
    ]
    assert all("Message pattern" in message["claim"] for message in payload["retrieved_messages"])


@pytest.mark.parametrize("expected_key", tuple(QUICK_PROMPT_CASES))
def test_copilot_missing_member_responses_do_not_invent_or_retrieve_messages(
    expected_key: str,
) -> None:
    case = QUICK_PROMPT_CASES[expected_key]
    payload = answer_copilot(member_id="Member:missing", question=str(case["question"]))

    _assert_payload_contract(payload)
    assert payload["member_id"] == "Member:missing"
    assert payload["quick_prompt_key"] == expected_key
    assert payload["fact_cards"] == [
        {
            "claim": "The graph has no supporting fact for Member:missing.",
            "confidence": "deterministic",
            "source_nodes": (),
            "query": (
                "copilot.unknown"
                if expected_key == "unknown"
                else case["fact_query"]
            ),
        }
    ]
    assert payload["chart_series"] == []
    assert payload["retrieved_messages"] == []
    assert "Jordan" not in payload["fact_cards"][0]["claim"]


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

    _assert_payload_contract(payload)
    assert payload["question"] == "Sleep this week"
    assert payload["chart_series"][0]["key"] == "sleep_this_week"
    assert payload["answer_constraints"]["summarize_only_fact_cards"] is True
