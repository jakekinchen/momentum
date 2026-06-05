from __future__ import annotations

import json
from pathlib import Path
import subprocess


REPO_ROOT = Path(__file__).resolve().parents[1]


def load_dashboard_fixture() -> dict:
    """Load the dashboard JS fixture through Node so tests use the shipped file."""

    script = """
const fs = require("node:fs");
const vm = require("node:vm");
const fixturePath = process.argv[1];
const context = { window: {} };
vm.createContext(context);
vm.runInContext(fs.readFileSync(fixturePath, "utf8"), context, { filename: fixturePath });
process.stdout.write(JSON.stringify(context.window.FITGRAPH_DEMO));
"""
    result = subprocess.run(
        ["node", "-e", script, str(REPO_ROOT / "dashboard/fixtures/demo.js")],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def run_dashboard_dom_harness() -> dict:
    """Execute the dependency-free dashboard DOM harness and return its report."""

    result = subprocess.run(
        ["node", str(REPO_ROOT / "tests/fixtures/dashboard_dom_harness.mjs")],
        check=True,
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)
