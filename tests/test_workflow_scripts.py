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


def _next_resume_brief_for_slug(slug: str) -> str:
    result = _run(["bash", "scripts/plan_next_resume_brief.sh", slug])
    for line in result.stdout.splitlines():
        if line.startswith("next brief: "):
            return line.split(": ", 1)[1]
    raise AssertionError("planner did not print next brief")


def _valid_resume_brief(
    brief_path: str = "docs/briefs/007-verified-ontology-lock.md",
) -> str:
    return f"""# Human-Approved Resume Brief

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
- `{brief_path}`

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
- Run `bash scripts/validate_resume_brief.sh {brief_path}`.
- Run `bash scripts/agent_thread_status.sh`.
"""


def _write_minimal_workflow_root(
    root: Path,
    *,
    agents: str | None = None,
    readme: str | None = None,
) -> None:
    default_agents = """# AGENTS.md

- Run `bash scripts/agent_thread_status.sh`.
- Read `docs/agent-thread-handoff.md`.
- Respect `<stop-orchestrator/>`.
- Validate drafted resume briefs with `bash scripts/validate_resume_brief.sh`.
"""
    default_readme = """# FitGraph KG

- Start with `bash scripts/agent_thread_status.sh`.
- Read `docs/agent-thread-handoff.md`.
- Respect `<stop-orchestrator/>`.
- Validate drafted resume briefs with `bash scripts/validate_resume_brief.sh <planner-next-brief-path>`.
"""
    default_handoff = """# Handoff

After drafting a candidate resume brief, validate it:

```bash
bash scripts/validate_resume_brief.sh <planner-next-brief-path>
```
"""
    default_devops = """# Devops

Resume-brief validation requires a drafted candidate brief:

```bash
bash scripts/validate_resume_brief.sh <planner-next-brief-path>
```
"""
    files = {
        "AGENTS.md": agents if agents is not None else default_agents,
        "README.md": readme if readme is not None else default_readme,
        "GOAL.md": (
            "# GOAL\n\n"
            "<stop-orchestrator/>\n\n"
            "## Current Slice\n\n"
            "docs/briefs/006-m5-ontology-sidecar-validation.md\n"
        ),
        "docs/kg-module-prd.md": "# PRD\n",
        "docs/agent-thread-handoff.md": default_handoff,
        "executor-reviewer-pair-programming.md": "# Pair\n",
        "docs/briefs/000-template-human-approved-resume.md": "# Template\n",
        "docs/briefs/006-m5-ontology-sidecar-validation.md": "# Active brief\n",
        "docs/autonomous-workflow/README.md": "# Workflow\n",
        "docs/autonomous-workflow/01-operating-model.md": "# Operating\n",
        "docs/autonomous-workflow/02-role-contracts.md": "# Roles\n",
        "docs/autonomous-workflow/03-planning-system.md": "# Planning\n",
        "docs/autonomous-workflow/04-execution-protocol.md": "# Execution\n",
        "docs/autonomous-workflow/05-devops-and-session-ops.md": default_devops,
        "docs/autonomous-workflow/06-manager-guardian-protocol.md": "# Manager\n",
        "docs/autonomous-workflow/07-document-and-artifact-map.md": "# Artifacts\n",
        "docs/autonomous-workflow/08-scaffold-adoption-matrix.md": "# Matrix\n",
        "docs/autonomous-workflow/09-fitgraph-autonomous-plan.md": "## M0 - Test\n",
        "scripts/audit_codex_pair_state.mjs": "console.log('ok')\n",
        "pyproject.toml": "[project]\nname = \"fitgraph-test\"\nversion = \"0.0.0\"\n",
    }
    executable_scripts = {
        "scripts/agent_thread_status.sh": "#!/usr/bin/env bash\n",
        "scripts/audit_autonomous_workflow.sh": "#!/usr/bin/env bash\n",
        "scripts/plan_next_resume_brief.sh": "#!/usr/bin/env bash\n",
        "scripts/validate_resume_brief.sh": "#!/usr/bin/env bash\n",
        "scripts/run_codex_pair_cycle.sh": "#!/usr/bin/env bash\n",
        "scripts/start_codex_goal_loop.sh": (
            "#!/usr/bin/env bash\n"
            "printf 'Refusing to start Codex goal loop\\n'\n"
        ),
        "scripts/stop_codex_goal_loop.sh": "#!/usr/bin/env bash\n",
    }
    for path, text in {**files, **executable_scripts}.items():
        target = root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")
    for path in executable_scripts:
        (root / path).chmod(0o755)
    for directory in (
        "docs/session-logs",
        "docs/reviewer-messages",
        "docs/manager-log",
    ):
        (root / directory).mkdir(parents=True, exist_ok=True)
    _run(["git", "init", "--quiet"], cwd=root)


def test_agent_thread_status_reports_stop_state_and_audits() -> None:
    expected_resume_brief = _next_resume_brief_for_slug("verified-ontology-lock")
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
        f"bash scripts/validate_resume_brief.sh {expected_resume_brief}"
    ) in result.stdout
    assert "workflow audit clean" in result.stdout
    assert "== Pair State Audit ==" in result.stdout
    assert "agent thread status clean" in result.stdout


def test_agent_thread_status_fallback_avoids_stale_resume_target(
    tmp_path: Path,
) -> None:
    _write_minimal_workflow_root(tmp_path)

    result = _run(["bash", "scripts/agent_thread_status.sh", str(tmp_path)])

    assert (
        "resume brief validation example: "
        "bash scripts/validate_resume_brief.sh <planner-next-brief-path>"
    ) in result.stdout
    assert (
        "bash scripts/validate_resume_brief.sh docs/briefs/007-verified-ontology-lock.md"
        not in result.stdout
    )
    assert "agent thread status clean" in result.stdout


def test_agents_md_points_future_threads_to_status_handoff() -> None:
    agents = (REPO_ROOT / "AGENTS.md").read_text(encoding="utf-8")

    assert "bash scripts/agent_thread_status.sh" in agents
    assert "docs/agent-thread-handoff.md" in agents
    assert "<stop-orchestrator/>" in agents
    assert "bash scripts/validate_resume_brief.sh" in agents


def test_readme_points_future_threads_to_status_handoff() -> None:
    readme = (REPO_ROOT / "README.md").read_text(encoding="utf-8")

    assert "bash scripts/agent_thread_status.sh" in readme
    assert "docs/agent-thread-handoff.md" in readme
    assert "<stop-orchestrator/>" in readme
    assert "uv run python -m kg.validation" in readme
    assert "bash scripts/validate_resume_brief.sh" in readme
    assert "bash scripts/validate_resume_brief.sh <planner-next-brief-path>" in readme
    assert (
        "bash scripts/validate_resume_brief.sh docs/briefs/007-verified-ontology-lock.md"
        not in readme
    )
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
    after_drafting = handoff.split("After drafting a candidate resume brief", 1)[1]

    assert "bash scripts/audit_autonomous_workflow.sh" in direct_audits
    assert "bash scripts/plan_next_resume_brief.sh verified-ontology-lock" in direct_audits
    assert "bash scripts/validate_resume_brief.sh" not in direct_audits
    assert "After drafting a candidate resume brief" in handoff
    assert "bash scripts/validate_resume_brief.sh <planner-next-brief-path>" in after_drafting
    assert (
        "bash scripts/validate_resume_brief.sh docs/briefs/007-verified-ontology-lock.md"
        not in handoff
    )


def test_devops_docs_separate_safe_commands_from_loop_commands() -> None:
    devops = (
        REPO_ROOT / "docs/autonomous-workflow/05-devops-and-session-ops.md"
    ).read_text(encoding="utf-8")
    safe_commands = devops.split("Stopped-state safe commands:", 1)[1]
    safe_commands = safe_commands.split("Resume-brief validation requires", 1)[0]
    loop_commands = devops.split("Start/run loop commands require", 1)[1]

    assert "bash scripts/agent_thread_status.sh" in safe_commands
    assert "bash scripts/stop_codex_goal_loop.sh" in safe_commands
    assert "bash scripts/validate_resume_brief.sh <planner-next-brief-path>" in devops
    assert (
        "bash scripts/validate_resume_brief.sh docs/briefs/007-verified-ontology-lock.md"
        not in devops
    )
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
    assert (
        "Update GOAL.md to point Current Slice at docs/briefs/007-<slice-name>.md"
        not in result.stdout
    )
    assert "git add docs/briefs/007-<slice-name>.md GOAL.md" not in result.stdout
    assert (
        "Update GOAL.md to point Current Slice at the drafted candidate brief "
        "after rerunning with a concrete slug"
    ) in result.stdout
    assert "git add <planner-next-brief-path> GOAL.md" in result.stdout


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
    assert "ok   resume brief self-validation command targets candidate" in result.stdout
    assert "ok   resume checklist self-validation command targets candidate" in result.stdout
    assert "stop sentinel: present" in result.stdout


def test_resume_brief_validator_accepts_wrapped_vector_guardrail(
    tmp_path: Path,
) -> None:
    brief_dir = tmp_path / "docs/briefs"
    brief_dir.mkdir(parents=True)
    brief_path = brief_dir / "007-wrapped-vector.md"
    wrapped_brief = _valid_resume_brief("docs/briefs/007-wrapped-vector.md").replace(
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
    missing_command = _valid_resume_brief(
        "docs/briefs/007-missing-self-validation.md"
    ).replace(
        "- Run `bash scripts/validate_resume_brief.sh docs/briefs/007-missing-self-validation.md`.\n",
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
    assert "MISS resume brief self-validation command targets candidate" in result.stdout
    assert "MISS resume checklist self-validation command targets candidate" in result.stdout
    assert "resume brief validation warnings:" in result.stdout


def test_resume_brief_validator_rejects_wrong_self_validation_target(
    tmp_path: Path,
) -> None:
    brief_dir = tmp_path / "docs/briefs"
    brief_dir.mkdir(parents=True)
    brief_path = brief_dir / "007-self-validation-target.md"
    wrong_target = _valid_resume_brief("docs/briefs/008-wrong.md")
    brief_path.write_text(wrong_target, encoding="utf-8")

    result = _run(
        [
            "bash",
            "scripts/validate_resume_brief.sh",
            "docs/briefs/007-self-validation-target.md",
            str(tmp_path),
        ],
        check=False,
    )

    assert result.returncode == 1
    assert "ok   resume brief self-validation command present" in result.stdout
    assert "MISS resume brief self-validation command targets candidate" in result.stdout
    assert "MISS resume checklist self-validation command targets candidate" in result.stdout
    assert "resume brief validation warnings:" in result.stdout


def test_resume_brief_validator_requires_self_validation_target_in_checklist(
    tmp_path: Path,
) -> None:
    brief_dir = tmp_path / "docs/briefs"
    brief_dir.mkdir(parents=True)
    brief_path = brief_dir / "007-checklist-target.md"
    candidate_path = "docs/briefs/007-checklist-target.md"
    checklist_missing_target = _valid_resume_brief(candidate_path).replace(
        f"- Run `bash scripts/validate_resume_brief.sh {candidate_path}`.",
        "- Run `bash scripts/agent_thread_status.sh`.",
    )
    checklist_missing_target = checklist_missing_target.replace(
        "```bash\nuv run pytest\n",
        f"```bash\nbash scripts/validate_resume_brief.sh {candidate_path}\nuv run pytest\n",
    )
    brief_path.write_text(checklist_missing_target, encoding="utf-8")

    result = _run(
        [
            "bash",
            "scripts/validate_resume_brief.sh",
            candidate_path,
            str(tmp_path),
        ],
        check=False,
    )

    assert result.returncode == 1
    assert "ok   resume brief self-validation command present" in result.stdout
    assert "ok   resume brief self-validation command targets candidate" in result.stdout
    assert "MISS resume checklist self-validation command targets candidate" in result.stdout
    assert "resume brief validation warnings:" in result.stdout


def test_resume_brief_validator_rejects_vector_safety_enforcement(
    tmp_path: Path,
) -> None:
    brief_dir = tmp_path / "docs/briefs"
    brief_dir.mkdir(parents=True)
    brief_path = brief_dir / "007-vector-safety.md"
    unsafe_brief = _valid_resume_brief("docs/briefs/007-vector-safety.md").replace(
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
    assert "ok   AGENTS.md points to agent status" in result.stdout
    assert "ok   AGENTS.md points to handoff" in result.stdout
    assert "ok   AGENTS.md preserves stop sentinel guidance" in result.stdout
    assert "ok   AGENTS.md points to resume brief validation" in result.stdout
    assert "ok   README.md points to agent status" in result.stdout
    assert "ok   README.md points to handoff" in result.stdout
    assert "ok   README.md preserves stop sentinel guidance" in result.stdout
    assert "ok   README.md points to resume brief validation" in result.stdout
    assert "ok   README.md uses planner resume-validation target" in result.stdout
    assert "ok   README.md avoids stale hardcoded resume-validation target" in result.stdout
    assert "ok   docs/agent-thread-handoff.md uses planner resume-validation target" in result.stdout
    assert (
        "ok   docs/agent-thread-handoff.md avoids stale hardcoded resume-validation target"
        in result.stdout
    )
    assert (
        "ok   docs/autonomous-workflow/05-devops-and-session-ops.md uses planner resume-validation target"
        in result.stdout
    )
    assert (
        "ok   docs/autonomous-workflow/05-devops-and-session-ops.md avoids stale hardcoded resume-validation target"
        in result.stdout
    )
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


def test_workflow_audit_requires_entrypoint_guidance_content(tmp_path: Path) -> None:
    _write_minimal_workflow_root(
        tmp_path,
        agents="# AGENTS.md\n\nMissing current handoff guidance.\n",
        readme="# FitGraph KG\n\nMissing current handoff guidance.\n",
    )

    result = _run(
        ["bash", "scripts/audit_autonomous_workflow.sh", str(tmp_path)],
        check=False,
    )

    assert result.returncode == 1
    assert "MISS AGENTS.md points to agent status" in result.stdout
    assert "MISS AGENTS.md points to handoff" in result.stdout
    assert "MISS AGENTS.md preserves stop sentinel guidance" in result.stdout
    assert "MISS AGENTS.md points to resume brief validation" in result.stdout
    assert "MISS README.md points to agent status" in result.stdout
    assert "MISS README.md points to handoff" in result.stdout
    assert "MISS README.md preserves stop sentinel guidance" in result.stdout
    assert "MISS README.md points to resume brief validation" in result.stdout
    assert "MISS README.md uses planner resume-validation target" in result.stdout
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
