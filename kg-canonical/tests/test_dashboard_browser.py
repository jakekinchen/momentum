from __future__ import annotations

from tests.dashboard_test_helpers import load_dashboard_fixture, run_dashboard_dom_harness


def test_dashboard_dom_harness_renders_required_sections_and_charts() -> None:
    fixture = load_dashboard_fixture()
    report = run_dashboard_dom_harness()
    initial = report["initial"]

    assert initial["runId"] == fixture["meta"]["runId"]
    assert initial["graphVersion"] == fixture["meta"]["graphVersion"]
    assert initial["ontologyLock"] == fixture["meta"]["ontologyLockVersion"]
    assert initial["memberTitle"] == "Jordan Rivera | 1:1 Coaching"
    assert initial["planCards"] == len(fixture["generation"]["selected"])
    assert initial["receiptRows"] == len(fixture["generation"]["receipts"])
    assert initial["alternatives"] == len(fixture["generation"]["alternatives"])
    assert initial["prompts"] == fixture["copilot"]["prompts"]
    assert initial["factCards"] == len(
        fixture["copilot"]["responses"][fixture["copilot"]["prompts"][0]]["cards"]
    )
    assert initial["evidenceTitle"] == fixture["generation"]["receipts"][0]["label"]
    assert initial["charts"] == {
        "adherenceSvg": 1,
        "sleepBars": len(fixture["charts"]["sleep"]),
        "messageBars": len(fixture["charts"]["messages"]) * 2,
    }


def test_dashboard_dom_harness_exercises_receipt_filter_evidence_and_copilot() -> None:
    fixture = load_dashboard_fixture()
    report = run_dashboard_dom_harness()

    filtered_count = sum(
        1 for receipt in fixture["generation"]["receipts"] if receipt["decision"] == "filtered"
    )
    assert report["afterFiltered"]["activeFilter"] == "filtered"
    assert report["afterFiltered"]["receiptRows"] == filtered_count
    assert all("filtered" in row_text for row_text in report["afterFiltered"]["rowText"])

    evidence = report["afterEvidenceInspect"]
    assert evidence["evidenceTitle"] == "Kettlebell Deadlift"
    assert "Exercise:kettlebell_deadlift -VARIANT_OF-> ExerciseFamily:deadlift_family" in evidence[
        "evidenceText"
    ]
    assert "Coach prompt" in evidence["evidenceText"]

    copilot = report["afterCopilotPrompt"]
    assert copilot["activePrompt"] == "Churn risk"
    assert "Churn risk is elevated" in copilot["answer"]
    assert copilot["factCards"] == len(fixture["copilot"]["responses"]["Churn risk"]["cards"])
    assert "member_retrieval.churn_risk" in copilot["factText"]

    assert report["afterGenerate"]["lastRun"] == "Generated now"
