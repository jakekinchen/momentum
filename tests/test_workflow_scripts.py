from __future__ import annotations

from pathlib import Path
import subprocess


REPO_ROOT = Path(__file__).resolve().parents[1]


def _markdown_section(text: str, heading: str) -> str:
    start_marker = f"## {heading}\n"
    start = text.index(start_marker) + len(start_marker)
    end = text.find("\n## ", start)
    if end == -1:
        end = len(text)
    return text[start:end]


def _run(command: list[str], *, check: bool = True, cwd: Path = REPO_ROOT) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        check=check,
        cwd=cwd,
        capture_output=True,
        text=True,
    )


def _valid_resume_brief() -> str:
    return """# Human-Approved Resume Brief

**Date:** 2026-06-04

## Human Direction

User explicitly asked to resume the verified ontology-lock slice.

## Objective

Create the smallest verified ontology-lock planning slice.

## Product / Project Value

This keeps FitGraph moving toward the PRD while preserving deterministic graph behavior.

## Acceptance Criteria

- Preserve deterministic graph behavior over LLM-driven eligibility.
- Preserve `MAPS_TO` as ontology audit metadata.
- Do not claim verified ontology metadata unless `graph/ontology-lock.json` contains it.

## Expected Files

- `GOAL.md`
- `docs/briefs/007-verified-ontology-lock.md`

## Validation Commands

```bash
uv run pytest
uv run python -m kg.validation
bash scripts/audit_autonomous_workflow.sh
node scripts/audit_codex_pair_state.mjs
```

## Evidence To Record

- Validation command output.
- Confirmation that Vector search must not enforce safety.

## Reachability / Demo Proof

Run the workflow audit and KG validation commands.

## Out Of Scope

- Runtime graph behavior changes.
- Ontology ID claims not pinned in `graph/ontology-lock.json`.

## Stop Conditions

- Human direction is missing.
- The slice would replace deterministic safety enforcement with vector behavior.

## Resume Checklist

- Update `GOAL.md`.
- Run `bash scripts/validate_resume_brief.sh docs/briefs/007-verified-ontology-lock.md`.
- Run `bash scripts/agent_thread_status.sh`.
"""


def test_agent_thread_status_reports_stop_state_and_audits() -> None:
    result = _run(["bash", "scripts/agent_thread_status.sh"])

    assert "handoff: docs/agent-thread-handoff.md" in result.stdout
    assert "stop sentinel: present" in result.stdout
    assert "executor product slices: stopped until fresh human direction" in result.stdout
    assert (
        "resume plan example: "
        "bash scripts/plan_next_resume_brief.sh verified-ontology-lock"
    ) in result.stdout
    assert (
        "resume brief validation example: "
        "bash scripts/validate_resume_brief.sh "
        "docs/briefs/007-verified-ontology-lock.md"
    ) in result.stdout
    assert "workflow audit clean" in result.stdout
    assert "== Pair State Audit ==" in result.stdout
    assert "agent thread status clean" in result.stdout


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
    assert "bash scripts/validate_resume_brief.sh" in readme
    assert "final clean/warning summary" in readme


def test_readme_safe_checks_do_not_require_candidate_resume_brief() -> None:
    readme = (REPO_ROOT / "README.md").read_text(encoding="utf-8")
    safe_checks = _markdown_section(readme, "Safe Checks")

    assert "uv run pytest" in safe_checks
    assert "bash scripts/audit_autonomous_workflow.sh" in safe_checks
    assert "bash scripts/plan_next_resume_brief.sh verified-ontology-lock" in safe_checks
    assert "bash scripts/validate_resume_brief.sh" not in safe_checks
    assert "requires a drafted candidate brief path" in safe_checks


def test_handoff_direct_audits_do_not_require_candidate_resume_brief() -> None:
    handoff = (REPO_ROOT / "docs/agent-thread-handoff.md").read_text(encoding="utf-8")
    direct_audits = handoff.split("You can also run the underlying audits directly:", 1)[1]
    direct_audits = direct_audits.split("After drafting a candidate resume brief", 1)[0]

    assert "bash scripts/audit_autonomous_workflow.sh" in direct_audits
    assert "bash scripts/plan_next_resume_brief.sh verified-ontology-lock" in direct_audits
    assert "bash scripts/validate_resume_brief.sh" not in direct_audits
    assert "After drafting a candidate resume brief" in handoff


def test_devops_docs_separate_safe_commands_from_loop_commands() -> None:
    devops = (
        REPO_ROOT / "docs/autonomous-workflow/05-devops-and-session-ops.md"
    ).read_text(encoding="utf-8")
    safe_commands = devops.split("Stopped-state safe commands:", 1)[1]
    safe_commands = safe_commands.split("Resume-brief validation requires", 1)[0]
    loop_commands = devops.split("Start/run loop commands require", 1)[1]

    assert "bash scripts/agent_thread_status.sh" in safe_commands
    assert "bash scripts/stop_codex_goal_loop.sh" in safe_commands
    assert "bash scripts/run_codex_pair_cycle.sh --once" not in safe_commands
    assert "bash scripts/start_codex_goal_loop.sh --max-cycles 3" in loop_commands
    assert "bash scripts/stop_codex_goal_loop.sh" not in loop_commands
    assert "stop sentinel is absent" in devops


def test_resume_template_preserves_human_approval_guardrails() -> None:
    template = (
        REPO_ROOT / "docs/briefs/000-template-human-approved-resume.md"
    ).read_text(encoding="utf-8")

    assert "## Human Direction" in template
    assert "fresh human direction" in template
    assert "<stop-orchestrator/>" in template
    assert "docs/briefs/007-<slice-name>.md" in template
    assert "bash scripts/validate_resume_brief.sh docs/briefs/007-<slice-name>.md" in template
    assert "uv run python -m kg.validation" in template


def test_resume_plan_script_reports_next_brief_without_mutating() -> None:
    brief_numbers = [
        int(path.name[:3])
        for path in (REPO_ROOT / "docs/briefs").glob("[0-9][0-9][0-9]-*.md")
        if not path.name.startswith("000-template-")
    ]
    next_number = max(brief_numbers, default=0) + 1
    expected_target = f"docs/briefs/{next_number:03d}-agent-thread-test.md"
    target_path = REPO_ROOT / expected_target

    result = _run(["bash", "scripts/plan_next_resume_brief.sh", "agent-thread-test"])

    assert "mode: dry-run (no files written)" in result.stdout
    assert "stop sentinel: present" in result.stdout
    assert f"next brief: {expected_target}" in result.stdout
    assert (
        "copy command: cp docs/briefs/000-template-human-approved-resume.md "
        f"{expected_target}"
    ) in result.stdout
    assert (
        f"Run: bash scripts/validate_resume_brief.sh {expected_target}"
        in result.stdout
    )
    assert (
        f"bash scripts/validate_resume_brief.sh {expected_target}"
        in result.stdout
    )
    assert f"git add {expected_target} GOAL.md" in result.stdout
    assert not target_path.exists()


def test_resume_plan_without_slug_avoids_placeholder_validation_command() -> None:
    result = _run(["bash", "scripts/plan_next_resume_brief.sh"])

    assert "mode: dry-run (no files written)" in result.stdout
    assert (
        "choose slug: bash scripts/plan_next_resume_brief.sh verified-ontology-lock"
        in result.stdout
    )
    assert (
        "Rerun with a lowercase slug to print the exact resume-brief validation command"
    ) in result.stdout
    assert (
        "bash scripts/validate_resume_brief.sh docs/briefs/007-<slice-name>.md"
        not in result.stdout
    )


def test_resume_brief_validator_accepts_de_templated_candidate(tmp_path: Path) -> None:
    brief_dir = tmp_path / "docs/briefs"
    brief_dir.mkdir(parents=True)
    brief_path = brief_dir / "007-verified-ontology-lock.md"
    brief_path.write_text(_valid_resume_brief(), encoding="utf-8")
    (tmp_path / "GOAL.md").write_text("# GOAL\n\n<stop-orchestrator/>\n", encoding="utf-8")

    result = _run(
        [
            "bash",
            "scripts/validate_resume_brief.sh",
            "docs/briefs/007-verified-ontology-lock.md",
            str(tmp_path),
        ]
    )

    assert "resume brief validation clean" in result.stdout
    assert "ok   human direction replaced with concrete instruction" in result.stdout
    assert "ok   no template placeholder: Replace this section" in result.stdout
    assert "ok   resume brief self-validation command present" in result.stdout
    assert "stop sentinel: present" in result.stdout


def test_resume_brief_validator_accepts_wrapped_vector_guardrail(
    tmp_path: Path,
) -> None:
    brief_dir = tmp_path / "docs/briefs"
    brief_dir.mkdir(parents=True)
    brief_path = brief_dir / "007-wrapped-vector.md"
    wrapped_brief = _valid_resume_brief().replace(
        "Confirmation that Vector search must not enforce safety.",
        (
            "The slice would replace deterministic safety enforcement with LLM, embedding,\n"
            "or vector retrieval behavior."
        ),
    )
    brief_path.write_text(wrapped_brief, encoding="utf-8")

    result = _run(
        [
            "bash",
            "scripts/validate_resume_brief.sh",
            "docs/briefs/007-wrapped-vector.md",
            str(tmp_path),
        ]
    )

    assert "resume brief validation clean" in result.stdout
    assert "ok   vector safety-enforcement guardrail present" in result.stdout


def test_resume_brief_validator_rejects_raw_template_copy(tmp_path: Path) -> None:
    brief_dir = tmp_path / "docs/briefs"
    brief_dir.mkdir(parents=True)
    brief_path = brief_dir / "007-agent-thread-test.md"
    template = (
        REPO_ROOT / "docs/briefs/000-template-human-approved-resume.md"
    ).read_text(encoding="utf-8")
    brief_path.write_text(template, encoding="utf-8")

    result = _run(
        [
            "bash",
            "scripts/validate_resume_brief.sh",
            "docs/briefs/007-agent-thread-test.md",
            str(tmp_path),
        ],
        check=False,
    )

    assert result.returncode == 1
    assert "MISS human direction replaced with concrete instruction" in result.stdout
    assert "MISS no template placeholder: YYYY-MM-DD" in result.stdout
    assert "MISS no template placeholder: Replace this section" in result.stdout
    assert "resume brief validation warnings:" in result.stdout


def test_resume_brief_validator_requires_self_validation_command(
    tmp_path: Path,
) -> None:
    brief_dir = tmp_path / "docs/briefs"
    brief_dir.mkdir(parents=True)
    brief_path = brief_dir / "007-missing-self-validation.md"
    missing_command = _valid_resume_brief().replace(
        "- Run `bash scripts/validate_resume_brief.sh docs/briefs/007-verified-ontology-lock.md`.\n",
        "",
    )
    brief_path.write_text(missing_command, encoding="utf-8")

    result = _run(
        [
            "bash",
            "scripts/validate_resume_brief.sh",
            "docs/briefs/007-missing-self-validation.md",
            str(tmp_path),
        ],
        check=False,
    )

    assert result.returncode == 1
    assert "MISS resume brief self-validation command present" in result.stdout
    assert "resume brief validation warnings:" in result.stdout


def test_resume_brief_validator_rejects_vector_safety_enforcement(
    tmp_path: Path,
) -> None:
    brief_dir = tmp_path / "docs/briefs"
    brief_dir.mkdir(parents=True)
    brief_path = brief_dir / "007-vector-safety.md"
    unsafe_brief = _valid_resume_brief().replace(
        "Confirmation that Vector search must not enforce safety.",
        "Use vector search for safety enforcement.",
    )
    brief_path.write_text(unsafe_brief, encoding="utf-8")

    result = _run(
        [
            "bash",
            "scripts/validate_resume_brief.sh",
            "docs/briefs/007-vector-safety.md",
            str(tmp_path),
        ],
        check=False,
    )

    assert result.returncode == 1
    assert "MISS vector safety-enforcement guardrail present" in result.stdout
    assert "MISS no unsafe vector safety enforcement claim" in result.stdout
    assert "ok   no unsafe vector retrieval enforcement claim" in result.stdout
    assert "resume brief validation warnings:" in result.stdout


def test_workflow_audit_requires_handoff_artifacts_and_stop_guard() -> None:
    result = _run(["bash", "scripts/audit_autonomous_workflow.sh"])

    assert "ok   README.md" in result.stdout
    assert "ok   docs/briefs/000-template-human-approved-resume.md" in result.stdout
    assert "ok   docs/agent-thread-handoff.md" in result.stdout
    assert "ok   scripts/agent_thread_status.sh" in result.stdout
    assert "ok   executable scripts/agent_thread_status.sh" in result.stdout
    assert "ok   executable scripts/plan_next_resume_brief.sh" in result.stdout
    assert "ok   executable scripts/validate_resume_brief.sh" in result.stdout
    assert "active brief: docs/briefs/006-m5-ontology-sidecar-validation.md" in result.stdout
    assert "ok   docs/briefs/006-m5-ontology-sidecar-validation.md" in result.stdout
    assert "ok   start loop stop guard present" in result.stdout
    assert "agent status: bash scripts/agent_thread_status.sh" in result.stdout
    assert "workflow audit clean" in result.stdout


def test_workflow_audit_exits_nonzero_on_missing_artifacts(tmp_path: Path) -> None:
    result = _run(
        ["bash", "scripts/audit_autonomous_workflow.sh", str(tmp_path)],
        check=False,
    )

    assert result.returncode == 1
    assert "MISS AGENTS.md" in result.stdout
    assert "MISS README.md" in result.stdout
    assert "workflow audit warnings:" in result.stdout


def test_workflow_audit_requires_goal_current_slice_file(tmp_path: Path) -> None:
    (tmp_path / "GOAL.md").write_text(
        "# GOAL\n\n"
        "## Current Slice\n\n"
        "docs/briefs/999-missing.md\n",
        encoding="utf-8",
    )

    result = _run(
        ["bash", "scripts/audit_autonomous_workflow.sh", str(tmp_path)],
        check=False,
    )

    assert result.returncode == 1
    assert "active brief: docs/briefs/999-missing.md" in result.stdout
    assert "MISS docs/briefs/999-missing.md" in result.stdout
    assert "workflow audit warnings:" in result.stdout


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
