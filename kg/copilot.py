"""Command contract for deterministic Coach Copilot fact-card demos."""

from __future__ import annotations

from dataclasses import asdict
import argparse
import json
from typing import Any

from kg import member_retrieval


def _prompt_key(question: str) -> str:
    normalized = question.strip().lower()
    if "brief" in normalized:
        return "brief"
    if "adherence" in normalized:
        return "adherence_trend"
    if "sleep" in normalized:
        return "sleep_this_week"
    if "churn" in normalized or "risk" in normalized:
        return "churn_risk"
    if "message" in normalized:
        return "message_pattern"
    if "last 4" in normalized or "last four" in normalized or "changed" in normalized:
        return "compare_last_4_weeks"
    if "equipment" in normalized:
        return "available_equipment"
    if "injur" in normalized or "knee" in normalized:
        return "active_injuries"
    return "unknown"


def _fallback_fact_cards(member_id: str, key: str) -> list[member_retrieval.FactCard]:
    if key == "available_equipment":
        return member_retrieval.available_equipment(member_id)
    if key == "active_injuries":
        return member_retrieval.active_injuries(member_id)
    return [
        member_retrieval.FactCard(
            claim=f"The graph has no supporting fact for {member_id}.",
            confidence="deterministic",
            source_nodes=(),
            query=f"copilot.{key}",
        )
    ]


def answer_copilot(
    *,
    member_id: str = "Member:jordan",
    question: str,
) -> dict[str, Any]:
    """Answer a Copilot query with deterministic fact cards and chart series."""

    key = _prompt_key(question)
    if key in {
        "brief",
        "adherence_trend",
        "sleep_this_week",
        "churn_risk",
        "message_pattern",
        "compare_last_4_weeks",
    }:
        fact_cards = member_retrieval.copilot_fact_cards(member_id, key)
        chart_series = member_retrieval.copilot_chart_series(member_id, key)
    else:
        fact_cards = _fallback_fact_cards(member_id, key)
        chart_series = []

    return {
        "member_id": member_id,
        "question": question,
        "quick_prompt_key": key,
        "fact_cards": [asdict(card) for card in fact_cards],
        "chart_series": [asdict(series) for series in chart_series],
        "retrieved_messages": [
            asdict(card)
            for card in member_retrieval.message_pattern(member_id)
            if card.source_nodes
        ],
        "answer_constraints": {
            "summarize_only_fact_cards": True,
            "invent_member_data": False,
            "llm_decides_eligibility": False,
            "vector_search_enforces_safety": False,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Answer a graph-backed FitGraph Copilot question.")
    parser.add_argument("--member", default="Member:jordan")
    parser.add_argument("--question", required=True)
    args = parser.parse_args()
    print(
        json.dumps(
            answer_copilot(member_id=args.member, question=args.question),
            indent=2,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
