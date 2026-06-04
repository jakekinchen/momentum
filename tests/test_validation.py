from __future__ import annotations

import json
import subprocess
import sys

from kg.validation import REQUIRED_SEED_FILES, health_summary


def test_health_summary_reports_required_seed_files() -> None:
    summary = health_summary()

    assert summary["graph_version"] == "fitgraph-kg-m0-skeleton-v0"
    assert summary["ruleset_version"] == "ruleset-m0-placeholder-v0"
    assert summary["ontology_lock_version"] == "ontology-lock-m0-unverified"
    assert summary["ontology_status"] == "todo_unverified"
    assert summary["verified"] is False
    assert summary["validation_status"] == "pass"
    assert summary["required_seed_count"] == len(REQUIRED_SEED_FILES)
    assert summary["present_seed_count"] == len(REQUIRED_SEED_FILES)
    assert summary["parseable_seed_count"] == len(REQUIRED_SEED_FILES)
    assert set(summary["seed_files"]) == set(REQUIRED_SEED_FILES)


def test_validation_module_is_reachable_as_command() -> None:
    result = subprocess.run(
        [sys.executable, "-m", "kg.validation"],
        check=True,
        capture_output=True,
        text=True,
    )
    summary = json.loads(result.stdout)

    assert summary["validation_status"] == "pass"
    assert summary["present_seed_count"] == len(REQUIRED_SEED_FILES)
