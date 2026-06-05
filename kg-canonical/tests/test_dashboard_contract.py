from __future__ import annotations

from kg.copilot import answer_copilot
from kg.validation import GRAPH_VERSION, RULESET_VERSION
from kg.workout_generator import generate_workout

from tests.dashboard_test_helpers import REPO_ROOT, load_dashboard_fixture


def test_dashboard_static_shell_contains_required_operational_sections() -> None:
    html = (REPO_ROOT / "dashboard/index.html").read_text(encoding="utf-8")

    required_labels = [
        "Member Context",
        "Workout Generator",
        "Run Summary",
        "Selected Safe Pool",
        "Provenance Trace",
        "Alternatives",
        "Coach Copilot",
        "Member Signals",
        "Evidence",
    ]
    for label in required_labels:
        assert label in html

    required_ids = [
        "coach-prompt",
        "constraint-list",
        "receipt-table",
        "alternatives-list",
        "copilot-prompts",
        "adherence-chart",
        "sleep-chart",
        "message-chart",
        "evidence-detail",
    ]
    for element_id in required_ids:
        assert f'id="{element_id}"' in html

    assert '<script src="./fixtures/demo.js"></script>' in html
    assert '<script src="./app.js"></script>' in html


def test_dashboard_fixture_has_source_backed_contract_shape() -> None:
    fixture = load_dashboard_fixture()
    generation = fixture["generation"]

    assert fixture["member"]["name"] == "Jordan Rivera"
    assert fixture["workoutRequest"]["minutes"] == 50
    assert fixture["meta"]["graphVersion"] == GRAPH_VERSION
    assert fixture["meta"]["rulesetVersion"] == RULESET_VERSION
    assert fixture["meta"]["ontologyLockVersion"] == "ontology-lock-m0-unverified"

    assert len(generation["selected"]) == generation["summary"]["selectedCount"]
    assert len(generation["alternatives"]) == generation["summary"]["alternativesCount"]
    assert generation["summary"]["unresolvedCount"] == 0
    assert generation["receipts"]
    assert {receipt["decision"] for receipt in generation["receipts"]} >= {"selected", "filtered"}

    selected_labels = {exercise["label"] for exercise in generation["selected"]}
    for alternative in generation["alternatives"]:
        assert alternative["alternative"] in selected_labels
        assert alternative["graphPaths"]

    for receipt in generation["receipts"]:
        assert receipt["sourceIds"], receipt["id"]
        assert receipt["reasonCodes"], receipt["id"]
        assert all(source_id in fixture["sources"] for source_id in receipt["sourceIds"])
        if receipt["decision"] == "filtered":
            assert receipt["graphPaths"], receipt["id"]


def test_dashboard_responsive_css_keeps_all_panels_reachable_on_mobile() -> None:
    css = (REPO_ROOT / "dashboard/styles.css").read_text(encoding="utf-8")

    assert "@media (max-width: 820px)" in css
    mobile_block = css.split("@media (max-width: 820px)", 1)[1]
    assert "grid-template-columns: 1fr;" in mobile_block
    for area in [
        '"member"',
        '"generator"',
        '"summary"',
        '"plan"',
        '"charts"',
        '"decisions"',
        '"alternatives"',
        '"copilot"',
        '"evidence"',
    ]:
        assert area in mobile_block


def test_dashboard_fixture_drift_against_graph_backed_outputs() -> None:
    fixture = load_dashboard_fixture()
    prompt = "Build a 50-minute lower-body session. Exclude deadlifts. Only DB and KB."
    workout = generate_workout(prompt=prompt, minutes=fixture["workoutRequest"]["minutes"])

    assert fixture["workoutRequest"]["prompt"].startswith(prompt)
    assert workout["graph_contract"] == {
        "eligibility_source": "deterministic_graph_traversal",
        "llm_decides_eligibility": False,
        "vector_search_enforces_safety": False,
    }
    assert workout["unresolved_concepts"] == []

    generator_reason_codes = {
        reason_code
        for receipt in workout["filtered_exercises"]
        for reason_code in receipt["reason_codes"]
    }
    fixture_reason_codes = {
        reason_code
        for receipt in fixture["generation"]["receipts"]
        for reason_code in receipt["reasonCodes"]
    }
    assert "ACTIVE_KNEE_RESTRICTION" in fixture_reason_codes & generator_reason_codes
    assert "ACTIVE_KNEE_HIGH_IMPACT_RESTRICTION" in fixture_reason_codes & generator_reason_codes
    assert "MISSING_EQUIPMENT:barbell" in fixture_reason_codes & generator_reason_codes

    adherence = answer_copilot(question="How is adherence trending?")
    sleep = answer_copilot(question="How did Jordan sleep this week?")
    churn = answer_copilot(question="What is the churn risk?")
    messages = answer_copilot(question="What is the message pattern?")

    assert [point["value"] for point in fixture["charts"]["adherence"]] == [
        point["y"] for point in adherence["chart_series"][0]["points"]
    ]
    assert [point["value"] for point in fixture["charts"]["sleep"]] == [
        point["y"] for point in sleep["chart_series"][0]["points"]
    ]
    assert fixture["copilot"]["responses"]["Churn risk"]["cards"][0]["query"] == churn["fact_cards"][0][
        "query"
    ]
    assert fixture["copilot"]["responses"]["Message pattern"]["cards"][0]["query"] == messages[
        "fact_cards"
    ][0]["query"]
    assert all(card["confidence"] == "deterministic" for card in churn["fact_cards"])
