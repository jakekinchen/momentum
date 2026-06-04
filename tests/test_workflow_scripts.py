from __future__ import annotations

from pathlib import Path
import subprocess


REPO_ROOT = Path(__file__).resolve().parents[1]


def _run(command: list[str], *, check: bool = True, cwd: Path = REPO_ROOT) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        check=check,
        cwd=cwd,
        capture_output=True,
        text=True,
    )


def test_agent_thread_status_reports_stop_state_and_audits() -> None:
    result = _run(["bash", "scripts/agent_thread_status.sh"])

    assert "handoff: docs/agent-thread-handoff.md" in result.stdout
    assert "stop sentinel: present" in result.stdout
    assert "executor product slices: stopped until fresh human direction" in result.stdout
    assert "workflow audit clean" in result.stdout
    assert "== Pair State Audit ==" in result.stdout


def test_agents_md_points_future_threads_to_status_handoff() -> None:
    agents = (REPO_ROOT / "AGENTS.md").read_text(encoding="utf-8")

    assert "bash scripts/agent_thread_status.sh" in agents
    assert "docs/agent-thread-handoff.md" in agents
    assert "<stop-orchestrator/>" in agents


def test_readme_points_future_threads_to_status_handoff() -> None:
    readme = (REPO_ROOT / "README.md").read_text(encoding="utf-8")

    assert "bash scripts/agent_thread_status.sh" in readme
    assert "docs/agent-thread-handoff.md" in readme
    assert "<stop-orchestrator/>" in readme
    assert "uv run python -m kg.validation" in readme


def test_workflow_audit_requires_handoff_artifacts_and_stop_guard() -> None:
    result = _run(["bash", "scripts/audit_autonomous_workflow.sh"])

    assert "ok   README.md" in result.stdout
    assert "ok   docs/agent-thread-handoff.md" in result.stdout
    assert "ok   scripts/agent_thread_status.sh" in result.stdout
    assert "ok   executable scripts/agent_thread_status.sh" in result.stdout
    assert "ok   start loop stop guard present" in result.stdout
    assert "agent status: bash scripts/agent_thread_status.sh" in result.stdout
    assert "workflow audit clean" in result.stdout


def test_start_goal_loop_refuses_before_spawning_when_stop_sentinel_present(
    tmp_path: Path,
) -> None:
    (tmp_path / "GOAL.md").write_text("# GOAL\n\n<stop-orchestrator/>\n", encoding="utf-8")

    result = _run(
        [
            "bash",
            "scripts/start_codex_goal_loop.sh",
            "--root",
            str(tmp_path),
            "--max-cycles",
            "1",
        ],
        check=False,
    )

    combined_output = result.stdout + result.stderr
    assert result.returncode == 1
    assert "Stop sentinel present in GOAL.md. Refusing to start Codex goal loop." in combined_output
    assert "Remove or replace <stop-orchestrator/> only after fresh human direction." in combined_output
    assert not (tmp_path / ".codex-goal-loop.pid").exists()
