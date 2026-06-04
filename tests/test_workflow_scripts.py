from __future__ import annotations

from pathlib import Path
import re
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


def _next_manager_log_for_slug(slug: str) -> str:
    result = _run(["bash", "scripts/plan_next_manager_log.sh", slug])
    for line in result.stdout.splitlines():
        if line.startswith("next manager log: "):
            return line.split(": ", 1)[1]
    raise AssertionError("manager log planner did not print next manager log")


def _latest_manager_log() -> str:
    logs = [
        path.relative_to(REPO_ROOT).as_posix()
        for path in (REPO_ROOT / "docs/manager-log").glob("[0-9][0-9][0-9]-*.md")
        if not path.name.startswith("000-template-")
    ]
    return sorted(logs)[-1]


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
- Review `docs/manager-log latest:` and run `review latest command:`.
- Use `next manager log template:` until rerunning with a lowercase support slug.
- Plan drafted resume briefs with `bash scripts/plan_next_resume_brief.sh`.
- Validate drafted resume briefs with `bash scripts/validate_resume_brief.sh <planner-next-brief-path>`.
"""
    default_readme = """# FitGraph KG

- Start with `bash scripts/agent_thread_status.sh`.
- Read `docs/agent-thread-handoff.md`.
- Respect `<stop-orchestrator/>`.
- Review `docs/manager-log latest:` and run `review latest command:`.
- Use `next manager log template:` until rerunning with a lowercase support slug.
- Validate drafted resume briefs with `bash scripts/validate_resume_brief.sh <planner-next-brief-path>`.
"""
    default_handoff = """# Handoff

manager-log planner/support-log
manager support log required: docs/manager-log/NNN-*.md
docs/manager-log latest:
review latest command:
next manager log template:

After drafting a candidate resume brief, validate it:

```bash
bash scripts/validate_resume_brief.sh <planner-next-brief-path>
```
"""
    default_devops = """# Devops

manager support log required: docs/manager-log/NNN-*.md
docs/manager-log latest:
review latest command:
next manager log template:

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
        "docs/manager-log/000-template-manager-support.md": (
            "# Manager Log NNN - Short Title\n\n"
            "## Status\n\n"
            "## Manager Action\n\n"
            "## Validation Evidence\n\n"
            "Replace each placeholder with the exact command outcome before committing.\n\n"
            "## Guardrail\n\n"
            "This is process support only.\n"
        ),
        "docs/autonomous-workflow/README.md": (
            "# Workflow\n\n"
            "The executor leaves a session log.\n"
            "The reviewer leaves an exact decision.\n"
            "When `GOAL.md` contains `<stop-orchestrator/>`, manager-support slices are process-only.\n"
            "Review `docs/manager-log latest:` first.\n"
            "Leave `docs/manager-log/NNN-*.md`.\n"
            "They do not require executor logs or reviewer decisions.\n"
        ),
        "docs/autonomous-workflow/01-operating-model.md": (
            "# Operating\n\n"
            "## Stopped State\n\n"
            "When `GOAL.md` contains `<stop-orchestrator/>`, executor product slices are stopped.\n"
            "Review `docs/manager-log latest:`.\n"
            "Leave `docs/manager-log/NNN-*.md`.\n"
        ),
        "docs/autonomous-workflow/02-role-contracts.md": (
            "# Roles\n\n"
            "## Manager Contract\n\n"
            "When `GOAL.md` contains `<stop-orchestrator/>`, keep work to manager process support.\n"
            "Review `docs/manager-log latest:` before writing a manager log.\n"
            "Run the printed `review latest command:`.\n"
            "Use `next manager log template:` until rerunning with a lowercase support slug.\n"
            "Use `bash scripts/plan_next_manager_log.sh`.\n"
        ),
        "docs/autonomous-workflow/03-planning-system.md": "# Planning\n",
        "docs/autonomous-workflow/04-execution-protocol.md": (
            "# Execution\n\n"
            "Run `bash scripts/agent_thread_status.sh`.\n"
            "If `GOAL.md` contains `<stop-orchestrator/>`, do not implement product work.\n"
            "Execution is stopped until fresh human direction changes the goal.\n"
        ),
        "docs/autonomous-workflow/05-devops-and-session-ops.md": default_devops,
        "docs/autonomous-workflow/06-manager-guardian-protocol.md": (
            "# Manager\n\n"
            "## Stopped-State Manager Support\n\n"
            "Stopped-state support must not start product execution.\n"
            "Write `docs/manager-log/NNN-*.md` for support turns.\n"
            "Manager-only support does not need executor session logs or reviewer decisions.\n"
            "Use `docs/manager-log/000-template-manager-support.md`.\n"
            "Review `docs/manager-log latest:` before writing a new support log.\n"
            "Use `next manager log template:` until rerunning with a lowercase support slug.\n"
            "Use `bash scripts/plan_next_manager_log.sh <support-slug>`.\n"
        ),
        "docs/autonomous-workflow/07-document-and-artifact-map.md": "# Artifacts\n",
        "docs/autonomous-workflow/08-scaffold-adoption-matrix.md": (
            "# Matrix\n\n"
            "`docs/briefs/006-m5-ontology-sidecar-validation.md`\n"
            "`<stop-orchestrator/>`\n"
            "`docs/manager-log latest:`\n"
            "M0-M5 complete\n"
        ),
        "docs/autonomous-workflow/09-fitgraph-autonomous-plan.md": "## M0 - Test\n",
        "scripts/audit_codex_pair_state.mjs": "console.log('ok')\n",
        "pyproject.toml": "[project]\nname = \"fitgraph-test\"\nversion = \"0.0.0\"\n",
    }
    executable_scripts = {
        "scripts/agent_thread_status.sh": (
            "#!/usr/bin/env bash\n"
            "printf 'resume plan dry run: bash scripts/plan_next_resume_brief.sh\\n'\n"
            "section() { printf '\\n== %s ==\\n' \"$1\"; }\n"
            "manager_log_plan_status=0\n"
            "resume_plan_status=0\n"
            "section \"Manager Log Planner\"\n"
            "bash scripts/plan_next_manager_log.sh || manager_log_plan_status=$?\n"
            "section \"Resume Brief Planner\"\n"
            "bash scripts/plan_next_resume_brief.sh || resume_plan_status=$?\n"
            "printf 'resume brief validation: "
            "bash scripts/validate_resume_brief.sh <planner-next-brief-path>\\n'\n"
        ),
        "scripts/audit_autonomous_workflow.sh": "#!/usr/bin/env bash\n",
        "scripts/plan_next_manager_log.sh": (
            "#!/usr/bin/env bash\n"
            "printf 'mode: dry-run (no files written)\\n'\n"
            "printf 'docs/manager-log/000-template-manager-support.md\\n'\n"
            "printf 'review latest command:\\n'\n"
            "printf 'next manager log: rerun with a lowercase slug to print exact path\\n'\n"
            "printf 'next manager log template: docs/manager-log/001-<support-slug>.md\\n'\n"
            "printf 'Review the latest manager log with the printed review latest command\\n'\n"
            "printf 'Fill the manager log Validation Evidence with the command outcomes\\n'\n"
            "printf 'Run: git diff --check\\n'\n"
            "printf 'Commit with exact paths after rerunning with a concrete slug\\n'\n"
        ),
        "scripts/plan_next_resume_brief.sh": (
            "#!/usr/bin/env bash\n"
            "printf 'choose slug: bash scripts/plan_next_resume_brief.sh next-slice-slug\\n'\n"
            "printf 'Rerun with a lowercase slug to print the exact resume-brief validation command\\n'\n"
            "printf 'next brief: rerun with a lowercase slug to print exact path\\n'\n"
            "printf 'next brief template:\\n'\n"
        ),
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
    result = _run(["bash", "scripts/agent_thread_status.sh"])

    assert "handoff: docs/agent-thread-handoff.md" in result.stdout
    assert "stop sentinel: present" in result.stdout
    assert "executor product slices: stopped until fresh human direction" in result.stdout
    assert "manager log plan dry run: bash scripts/plan_next_manager_log.sh" in result.stdout
    assert "== Manager Log Planner ==" in result.stdout
    assert "review latest command: sed -n '1,160p' docs/manager-log/" in result.stdout
    assert (
        "next manager log: rerun with a lowercase slug to print exact path"
        in result.stdout
    )
    assert "next manager log template: docs/manager-log/" in result.stdout
    assert "next manager log: docs/manager-log/" not in result.stdout
    assert "manager support log required: docs/manager-log/NNN-*.md" in result.stdout
    assert "resume plan dry run: bash scripts/plan_next_resume_brief.sh" in result.stdout
    assert "== Resume Brief Planner ==" in result.stdout
    assert "next brief: rerun with a lowercase slug to print exact path" in result.stdout
    assert "next brief template: docs/briefs/" in result.stdout
    assert (
        "resume plan with slug: "
        "bash scripts/plan_next_resume_brief.sh <lowercase-slice-slug>"
    ) in result.stdout
    assert (
        "resume plan slug example: "
        "bash scripts/plan_next_resume_brief.sh verified-ontology-lock"
        not in result.stdout
    )
    assert (
        "resume brief validation: "
        "bash scripts/validate_resume_brief.sh <planner-next-brief-path>"
    ) in result.stdout
    assert (
        "bash scripts/validate_resume_brief.sh docs/briefs/007-verified-ontology-lock.md"
        not in result.stdout
    )
    assert "workflow audit clean" in result.stdout
    assert "== Pair State Audit ==" in result.stdout
    assert "agent thread status clean" in result.stdout


def test_agent_thread_status_minimal_root_uses_neutral_resume_target(
    tmp_path: Path,
) -> None:
    _write_minimal_workflow_root(tmp_path)

    result = _run(["bash", "scripts/agent_thread_status.sh", str(tmp_path)])

    assert "manager log plan dry run: bash scripts/plan_next_manager_log.sh" in result.stdout
    assert "== Manager Log Planner ==" in result.stdout
    assert "review latest command:" in result.stdout
    assert (
        "next manager log: rerun with a lowercase slug to print exact path"
        in result.stdout
    )
    assert "next manager log template: docs/manager-log/001-<support-slug>.md" in result.stdout
    assert "next manager log: docs/manager-log/001-test.md" not in result.stdout
    assert "manager support log required: docs/manager-log/NNN-*.md" in result.stdout
    assert "== Resume Brief Planner ==" in result.stdout
    assert "next brief: rerun with a lowercase slug to print exact path" in result.stdout
    assert "next brief template:" in result.stdout
    assert (
        "resume plan with slug: "
        "bash scripts/plan_next_resume_brief.sh <lowercase-slice-slug>"
    ) in result.stdout
    assert (
        "resume brief validation: "
        "bash scripts/validate_resume_brief.sh <planner-next-brief-path>"
    ) in result.stdout
    assert (
        "bash scripts/validate_resume_brief.sh docs/briefs/007-verified-ontology-lock.md"
        not in result.stdout
    )
    assert "agent thread status clean" in result.stdout


def test_pair_state_audit_labels_latest_artifacts() -> None:
    result = _run(["node", "scripts/audit_codex_pair_state.mjs"])

    assert "docs/briefs latest:" in result.stdout
    assert "docs/session-logs latest:" in result.stdout
    assert "docs/reviewer-messages latest:" in result.stdout
    assert "docs/manager-log latest:" in result.stdout
    assert "docs/manager-log:" not in result.stdout


def test_agents_md_points_future_threads_to_status_handoff() -> None:
    agents = (REPO_ROOT / "AGENTS.md").read_text(encoding="utf-8")

    assert "bash scripts/agent_thread_status.sh" in agents
    assert "docs/agent-thread-handoff.md" in agents
    assert "<stop-orchestrator/>" in agents
    assert "bash scripts/plan_next_manager_log.sh" in agents
    assert "bash scripts/plan_next_resume_brief.sh" in agents
    assert "docs/manager-log/NNN-*.md" in agents
    assert "docs/manager-log latest:" in agents
    assert "next manager log template:" in agents
    assert "bash scripts/validate_resume_brief.sh" in agents
    assert "bash scripts/validate_resume_brief.sh <planner-next-brief-path>" in agents
    assert (
        "bash scripts/validate_resume_brief.sh docs/briefs/007-verified-ontology-lock.md"
        not in agents
    )


def test_readme_points_future_threads_to_status_handoff() -> None:
    readme = (REPO_ROOT / "README.md").read_text(encoding="utf-8")

    assert "bash scripts/agent_thread_status.sh" in readme
    assert "docs/agent-thread-handoff.md" in readme
    assert "<stop-orchestrator/>" in readme
    assert "uv run python -m kg.validation" in readme
    assert "bash scripts/plan_next_manager_log.sh" in readme
    assert "docs/manager-log/NNN-*.md" in readme
    assert "docs/manager-log latest:" in readme
    assert "review latest command:" in readme
    assert "next manager log template:" in readme
    assert "bash scripts/validate_resume_brief.sh" in readme
    assert "bash scripts/validate_resume_brief.sh <planner-next-brief-path>" in readme
    assert "bash scripts/plan_next_resume_brief.sh <lowercase-slice-slug>" in readme
    assert "bash scripts/plan_next_resume_brief.sh verified-ontology-lock" not in readme
    assert (
        "bash scripts/validate_resume_brief.sh docs/briefs/007-verified-ontology-lock.md"
        not in readme
    )
    assert "final clean/warning summary" in readme
    assert "resume-brief planner" in readme


def test_readme_safe_checks_do_not_require_candidate_resume_brief() -> None:
    readme = (REPO_ROOT / "README.md").read_text(encoding="utf-8")
    safe_checks = _markdown_section(readme, "Safe Checks")

    assert "uv run pytest" in safe_checks
    assert "bash scripts/audit_autonomous_workflow.sh" in safe_checks
    assert "bash scripts/plan_next_manager_log.sh" in safe_checks
    assert "bash scripts/plan_next_resume_brief.sh" in safe_checks
    assert "bash scripts/plan_next_resume_brief.sh verified-ontology-lock" not in safe_checks
    assert "bash scripts/validate_resume_brief.sh" not in safe_checks
    assert "requires a drafted candidate brief path" in safe_checks


def test_handoff_direct_audits_do_not_require_candidate_resume_brief() -> None:
    handoff = (REPO_ROOT / "docs/agent-thread-handoff.md").read_text(encoding="utf-8")
    direct_audits = handoff.split("You can also run the underlying audits directly:", 1)[1]
    direct_audits = direct_audits.split("After drafting a candidate resume brief", 1)[0]
    after_drafting = handoff.split("After drafting a candidate resume brief", 1)[1]

    assert "bash scripts/audit_autonomous_workflow.sh" in direct_audits
    assert "bash scripts/plan_next_manager_log.sh" in direct_audits
    assert "bash scripts/plan_next_resume_brief.sh" in direct_audits
    assert (
        "bash scripts/plan_next_resume_brief.sh verified-ontology-lock"
        not in direct_audits
    )
    assert "bash scripts/validate_resume_brief.sh" not in direct_audits
    assert "After drafting a candidate resume brief" in handoff
    assert "bash scripts/validate_resume_brief.sh <planner-next-brief-path>" in after_drafting
    assert (
        "bash scripts/plan_next_resume_brief.sh <lowercase-slice-slug>"
        in handoff
    )
    assert (
        "bash scripts/plan_next_resume_brief.sh verified-ontology-lock"
        not in handoff
    )
    assert "Product-stop snapshot recorded:" in handoff
    assert "Treat that command output as the current operational state" in handoff
    assert re.search(r"placeholder\s+resume-validation command", handoff) is None
    assert "passes the current collected test suite" in handoff
    assert re.search(r"collected [0-9]+ tests", handoff) is None
    assert "manager-log planner/support-log" in handoff
    assert "manager support log required: docs/manager-log/NNN-*.md" in handoff
    assert "docs/manager-log latest:" in handoff
    assert "review latest command:" in handoff
    assert "next manager log template:" in handoff
    assert "resume-brief planner dry run" in handoff
    assert (
        "bash scripts/validate_resume_brief.sh docs/briefs/007-verified-ontology-lock.md"
        not in handoff
    )


def test_workflow_audit_rejects_any_hardcoded_handoff_pytest_count(
    tmp_path: Path,
) -> None:
    _write_minimal_workflow_root(tmp_path)
    handoff = tmp_path / "docs/agent-thread-handoff.md"
    handoff.write_text(
        "# Handoff\n\n"
        "Product-stop snapshot recorded:\n"
        "Treat that command output as the current operational state\n"
        "manager-log planner/support-log\n"
        "manager support log required: docs/manager-log/NNN-*.md\n"
        "docs/manager-log latest:\n"
        "review latest command:\n"
        "passes the current collected test suite\n"
        "uv run pytest collected 64 tests and passed.\n"
        "bash scripts/validate_resume_brief.sh <planner-next-brief-path>\n",
        encoding="utf-8",
    )

    result = _run(
        ["bash", "scripts/audit_autonomous_workflow.sh", str(tmp_path)],
        check=False,
    )

    assert result.returncode == 1
    assert "MISS handoff avoids hardcoded pytest count" in result.stdout


def test_workflow_audit_rejects_placeholder_resume_validation_wording(
    tmp_path: Path,
) -> None:
    _write_minimal_workflow_root(tmp_path)
    handoff = tmp_path / "docs/agent-thread-handoff.md"
    handoff.write_text(
        "# Handoff\n\n"
        "Product-stop snapshot recorded:\n"
        "Treat that command output as the current operational state\n"
        "manager-log planner/support-log\n"
        "manager support log required: docs/manager-log/NNN-*.md\n"
        "docs/manager-log latest:\n"
        "review latest command:\n"
        "next manager log template:\n"
        "passes the current collected test suite\n"
        "placeholder\n"
        "resume-validation command\n"
        "bash scripts/validate_resume_brief.sh <planner-next-brief-path>\n",
        encoding="utf-8",
    )

    result = _run(
        ["bash", "scripts/audit_autonomous_workflow.sh", str(tmp_path)],
        check=False,
    )

    assert result.returncode == 1
    assert (
        "MISS handoff avoids placeholder resume-validation wording"
        in result.stdout
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
    assert "bash scripts/plan_next_manager_log.sh" in safe_commands
    assert "bash scripts/plan_next_resume_brief.sh" in safe_commands
    assert (
        "bash scripts/plan_next_resume_brief.sh verified-ontology-lock"
        not in safe_commands
    )
    assert "bash scripts/validate_resume_brief.sh <planner-next-brief-path>" in devops
    assert (
        "bash scripts/validate_resume_brief.sh docs/briefs/007-verified-ontology-lock.md"
        not in devops
    )
    assert "bash scripts/run_codex_pair_cycle.sh --once" not in safe_commands
    assert "bash scripts/start_codex_goal_loop.sh --max-cycles 3" in loop_commands
    assert "bash scripts/stop_codex_goal_loop.sh" not in loop_commands
    assert "stop sentinel is absent" in devops
    assert "manager support log required: docs/manager-log/NNN-*.md" in devops
    assert "docs/manager-log latest:" in devops
    assert "review latest command:" in devops
    assert "next manager log template:" in devops


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


def test_manager_log_plan_with_slug_prints_exact_candidate_paths() -> None:
    expected_latest = _latest_manager_log()
    expected_target = _next_manager_log_for_slug("manager-log-planner")
    target_path = REPO_ROOT / expected_target

    result = _run(["bash", "scripts/plan_next_manager_log.sh", "manager-log-planner"])

    assert "mode: dry-run (no files written)" in result.stdout
    assert "stop sentinel: present" in result.stdout
    assert "support mode: manager process support only" in result.stdout
    assert f"latest manager log: {expected_latest}" in result.stdout
    assert (
        f"review latest command: sed -n '1,160p' {expected_latest}"
        in result.stdout
    )
    assert (
        "Review the latest manager log with the printed review latest command"
        in result.stdout
    )
    assert f"next manager log: {expected_target}" in result.stdout
    assert (
        "copy command: cp docs/manager-log/000-template-manager-support.md "
        f"{expected_target}"
    ) in result.stdout
    assert "Fill the manager log Validation Evidence" in result.stdout
    assert "Run: git diff --check" in result.stdout
    assert f"git add {expected_target} <changed-support-paths>" in result.stdout
    assert not target_path.exists()


def test_manager_log_plan_without_slug_avoids_placeholder_exact_paths() -> None:
    result = _run(["bash", "scripts/plan_next_manager_log.sh"])

    assert "mode: dry-run (no files written)" in result.stdout
    assert (
        "choose slug: bash scripts/plan_next_manager_log.sh manager-log-template"
        in result.stdout
    )
    assert (
        "copy command: rerun with a lowercase slug to print an exact copy command"
        in result.stdout
    )
    assert (
        "next manager log: rerun with a lowercase slug to print exact path"
        in result.stdout
    )
    assert "next manager log template: docs/manager-log/" in result.stdout
    assert "next manager log: docs/manager-log/" not in result.stdout
    assert (
        "cp docs/manager-log/000-template-manager-support.md docs/manager-log/"
        not in result.stdout
    )
    assert "git add docs/manager-log/" not in result.stdout
    assert (
        "Review the latest manager log with the printed review latest command"
        in result.stdout
    )
    assert "Fill the manager log Validation Evidence" in result.stdout
    assert "Run: git diff --check" in result.stdout
    assert "git add <planner-next-manager-log-path> <changed-support-paths>" in result.stdout


def test_resume_plan_without_slug_avoids_placeholder_validation_command() -> None:
    result = _run(["bash", "scripts/plan_next_resume_brief.sh"])

    assert "mode: dry-run (no files written)" in result.stdout
    assert (
        "choose slug: bash scripts/plan_next_resume_brief.sh next-slice-slug"
        in result.stdout
    )
    assert (
        "choose slug: bash scripts/plan_next_resume_brief.sh verified-ontology-lock"
        not in result.stdout
    )
    assert (
        "next brief: rerun with a lowercase slug to print exact path"
        in result.stdout
    )
    assert "next brief template: docs/briefs/" in result.stdout
    assert "next brief: docs/briefs/" not in result.stdout
    assert (
        "Rerun with a lowercase slug to print the exact resume-brief validation command"
    ) in result.stdout
    assert (
        "bash scripts/validate_resume_brief.sh <planner-next-brief-path>"
        in result.stdout
    )
    assert (
        "bash scripts/validate_resume_brief.sh <candidate-brief-path>"
        not in result.stdout
    )
    assert (
        "Remove or replace <stop-orchestrator/> only after fresh human direction"
        in result.stdout
    )
    assert "only after human approval" not in result.stdout
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


def test_resume_brief_validator_accepts_explicit_vector_search_prohibition(
    tmp_path: Path,
) -> None:
    brief_dir = tmp_path / "docs/briefs"
    brief_dir.mkdir(parents=True)
    brief_path = brief_dir / "007-vector-prohibition.md"
    safe_brief = _valid_resume_brief(
        "docs/briefs/007-vector-prohibition.md"
    ).replace(
        "Confirmation that Vector search must not enforce safety.",
        "Do not use vector search for safety enforcement.",
    )
    brief_path.write_text(safe_brief, encoding="utf-8")

    result = _run(
        [
            "bash",
            "scripts/validate_resume_brief.sh",
            "docs/briefs/007-vector-prohibition.md",
            str(tmp_path),
        ]
    )

    assert "resume brief validation clean" in result.stdout
    assert "ok   vector safety-enforcement guardrail present" in result.stdout
    assert "ok   no unsafe vector safety enforcement claim" in result.stdout


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
    assert "ok   docs/manager-log/000-template-manager-support.md" in result.stdout
    assert "ok   docs/agent-thread-handoff.md" in result.stdout
    assert "ok   scripts/agent_thread_status.sh" in result.stdout
    assert "ok   executable scripts/agent_thread_status.sh" in result.stdout
    assert "ok   pair-state audit labels latest artifacts" in result.stdout
    assert "ok   executable scripts/plan_next_manager_log.sh" in result.stdout
    assert "ok   executable scripts/plan_next_resume_brief.sh" in result.stdout
    assert "ok   executable scripts/validate_resume_brief.sh" in result.stdout
    assert "ok   operating model defines stopped state" in result.stdout
    assert "ok   operating model preserves stop sentinel boundary" in result.stdout
    assert "ok   operating model stops executor product slices" in result.stdout
    assert "ok   operating model points manager turns to latest manager log" in result.stdout
    assert "ok   operating model requires manager support logs" in result.stdout
    assert "ok   execution protocol starts with agent status" in result.stdout
    assert "ok   execution protocol preserves stop sentinel boundary" in result.stdout
    assert "ok   execution protocol blocks product work while stopped" in result.stdout
    assert "ok   execution protocol requires fresh human direction to resume" in result.stdout
    assert "ok   role contracts define manager contract" in result.stdout
    assert "ok   manager role contract preserves stop sentinel boundary" in result.stdout
    assert "ok   manager role contract points to latest manager log" in result.stdout
    assert "ok   manager role contract points to manager log planner" in result.stdout
    assert "ok   workflow README explains executor evidence" in result.stdout
    assert "ok   workflow README explains reviewer evidence" in result.stdout
    assert "ok   workflow README preserves stop sentinel manager boundary" in result.stdout
    assert "ok   workflow README points manager turns to latest manager log" in result.stdout
    assert "ok   workflow README requires manager support logs" in result.stdout
    assert "ok   workflow README separates manager support evidence" in result.stdout
    assert "ok   scaffold matrix names current active brief" in result.stdout
    assert "ok   scaffold matrix preserves stop sentinel state" in result.stdout
    assert "ok   scaffold matrix points to latest manager log" in result.stdout
    assert "ok   scaffold matrix captures completed autonomous plan" in result.stdout
    assert "ok   scaffold matrix avoids stale M0 active brief" in result.stdout
    assert "ok   scaffold matrix avoids stale first-slice pending note" in result.stdout
    assert "ok   AGENTS.md points to agent status" in result.stdout
    assert "ok   AGENTS.md points to handoff" in result.stdout
    assert "ok   AGENTS.md preserves stop sentinel guidance" in result.stdout
    assert "ok   AGENTS.md points to manager log planner" in result.stdout
    assert "ok   AGENTS.md requires manager support logs" in result.stdout
    assert "ok   AGENTS.md points manager turns to latest manager log" in result.stdout
    assert (
        "ok   AGENTS.md points manager turns to latest review command"
        in result.stdout
    )
    assert "ok   AGENTS.md explains manager log template path" in result.stdout
    assert "ok   AGENTS.md points to resume brief validation" in result.stdout
    assert "ok   README.md points to agent status" in result.stdout
    assert "ok   README.md points to handoff" in result.stdout
    assert "ok   README.md preserves stop sentinel guidance" in result.stdout
    assert "ok   README.md points to manager log planner" in result.stdout
    assert "ok   README.md requires manager support logs" in result.stdout
    assert "ok   README.md points manager turns to latest manager log" in result.stdout
    assert (
        "ok   README.md points manager turns to latest review command"
        in result.stdout
    )
    assert "ok   README.md explains manager log template path" in result.stdout
    assert "ok   README.md points to resume brief validation" in result.stdout
    assert "ok   AGENTS.md points to resume brief planner" in result.stdout
    assert (
        "ok   handoff explains audited manager log entrypoint guidance"
        in result.stdout
    )
    assert "ok   handoff labels static product snapshot" in result.stdout
    assert "ok   handoff points live state to status output" in result.stdout
    assert "ok   handoff explains status manager support-log line" in result.stdout
    assert "ok   handoff points manager turns to latest manager log" in result.stdout
    assert "ok   handoff points manager turns to latest review command" in result.stdout
    assert "ok   handoff explains manager log template path" in result.stdout
    assert "ok   handoff keeps pytest expectation count-neutral" in result.stdout
    assert "ok   handoff avoids hardcoded pytest count" in result.stdout
    assert (
        "ok   handoff avoids placeholder resume-validation wording"
        in result.stdout
    )
    assert "ok   devops docs explain status manager support-log line" in result.stdout
    assert "ok   devops docs point manager turns to latest manager log" in result.stdout
    assert "ok   devops docs point manager turns to latest review command" in result.stdout
    assert "ok   devops docs explain manager log template path" in result.stdout
    assert "ok   AGENTS.md uses planner resume-validation target" in result.stdout
    assert (
        "ok   AGENTS.md avoids stale hardcoded resume-validation target"
        in result.stdout
    )
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
    assert (
        "ok   scripts/agent_thread_status.sh uses neutral resume planner dry run"
        in result.stdout
    )
    assert (
        "ok   scripts/agent_thread_status.sh uses neutral resume planner slug target"
        in result.stdout
    )
    assert (
        "ok   scripts/agent_thread_status.sh uses neutral resume-validation target"
        in result.stdout
    )
    assert (
        "ok   scripts/agent_thread_status.sh avoids hardcoded resume planner slug"
        in result.stdout
    )
    assert (
        "ok   scripts/agent_thread_status.sh avoids stale hardcoded resume-validation target"
        in result.stdout
    )
    assert "ok   resume planner uses neutral slug example" in result.stdout
    assert "ok   resume planner avoids no-slug validation target" in result.stdout
    assert "ok   resume planner avoids placeholder next path" in result.stdout
    assert "ok   resume planner shows placeholder path as template" in result.stdout
    assert "ok   resume planner avoids hardcoded resume planner slug" in result.stdout
    assert (
        "ok   resume planner avoids stale hardcoded resume-validation target"
        in result.stdout
    )
    assert "ok   scripts/agent_thread_status.sh points to manager log planner" in result.stdout
    assert "ok   scripts/agent_thread_status.sh runs manager log planner" in result.stdout
    assert (
        "ok   scripts/agent_thread_status.sh reports manager planner status"
        in result.stdout
    )
    assert (
        "ok   scripts/agent_thread_status.sh requires manager support logs"
        in result.stdout
    )
    assert "ok   manager protocol defines stopped-state support" in result.stdout
    assert "ok   manager protocol preserves stopped-state product boundary" in result.stdout
    assert "ok   manager protocol requires manager support logs" in result.stdout
    assert (
        "ok   manager protocol separates manager logs from executor/reviewer artifacts"
        in result.stdout
    )
    assert "ok   manager protocol points to manager log template" in result.stdout
    assert "ok   manager protocol points to latest manager log" in result.stdout
    assert "ok   manager protocol explains manager log template path" in result.stdout
    assert "ok   manager log template includes status" in result.stdout
    assert "ok   manager log template includes manager action" in result.stdout
    assert "ok   manager log template includes validation evidence" in result.stdout
    assert "ok   manager log template requires validation outcomes" in result.stdout
    assert "ok   manager log template includes guardrail" in result.stdout
    assert "ok   manager log template preserves stopped-state guardrail" in result.stdout
    assert "latest tracked manager log: docs/manager-log/" in result.stdout
    assert "ok   latest tracked manager log includes validation evidence" in result.stdout
    assert (
        "ok   latest tracked manager log avoids pending validation evidence"
        in result.stdout
    )
    assert "ok   latest tracked manager log avoids outcome placeholders" in result.stdout
    assert "ok   manager log planner is dry run" in result.stdout
    assert "ok   manager log planner uses manager support template" in result.stdout
    assert "ok   manager log planner prints latest manager log path" in result.stdout
    assert "ok   manager log planner prints latest review command" in result.stdout
    assert "ok   manager log planner requires latest log review" in result.stdout
    assert "ok   manager log planner avoids placeholder next path" in result.stdout
    assert "ok   manager log planner shows placeholder path as template" in result.stdout
    assert "ok   manager log planner avoids no-slug exact git add paths" in result.stdout
    assert "ok   manager log planner requires diff check" in result.stdout
    assert "ok   manager log planner requires evidence fill" in result.stdout
    assert "ok   manager log planner avoids placeholder exact git add target" in result.stdout
    assert "active brief: docs/briefs/006-m5-ontology-sidecar-validation.md" in result.stdout
    assert "ok   docs/briefs/006-m5-ontology-sidecar-validation.md" in result.stdout
    assert "ok   start loop stop guard present" in result.stdout
    assert "agent status: bash scripts/agent_thread_status.sh" in result.stdout
    assert "suggested checks:" in result.stdout
    assert "- uv run pytest" in result.stdout
    assert "- uv run python -m kg.validation" in result.stdout
    assert "suggested checks: uv sync && uv run pytest" not in result.stdout
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
    assert "MISS AGENTS.md points to resume brief planner" in result.stdout
    assert "MISS AGENTS.md points to resume brief validation" in result.stdout
    assert "MISS AGENTS.md uses planner resume-validation target" in result.stdout
    assert "MISS README.md points to agent status" in result.stdout
    assert "MISS README.md points to handoff" in result.stdout
    assert "MISS README.md preserves stop sentinel guidance" in result.stdout
    assert "MISS README.md points to resume brief validation" in result.stdout
    assert "MISS README.md uses planner resume-validation target" in result.stdout
    assert "workflow audit warnings:" in result.stdout


def test_workflow_audit_requires_neutral_status_resume_guidance(tmp_path: Path) -> None:
    _write_minimal_workflow_root(tmp_path)
    status_script = tmp_path / "scripts/agent_thread_status.sh"
    status_script.write_text(
        "#!/usr/bin/env bash\n"
        "printf 'resume plan example: "
        "bash scripts/plan_next_resume_brief.sh verified-ontology-lock\\n'\n"
        "printf 'resume brief validation example: "
        "bash scripts/validate_resume_brief.sh "
        "docs/briefs/007-verified-ontology-lock.md\\n'\n",
        encoding="utf-8",
    )
    status_script.chmod(0o755)

    result = _run(
        ["bash", "scripts/audit_autonomous_workflow.sh", str(tmp_path)],
        check=False,
    )

    assert result.returncode == 1
    assert (
        "MISS scripts/agent_thread_status.sh uses neutral resume planner dry run"
        in result.stdout
    )
    assert (
        "MISS scripts/agent_thread_status.sh uses neutral resume planner slug target"
        in result.stdout
    )
    assert (
        "MISS scripts/agent_thread_status.sh uses neutral resume-validation target"
        in result.stdout
    )
    assert (
        "MISS scripts/agent_thread_status.sh avoids hardcoded resume planner slug"
        in result.stdout
    )
    assert (
        "MISS scripts/agent_thread_status.sh avoids stale hardcoded resume-validation target"
        in result.stdout
    )
    assert "workflow audit warnings:" in result.stdout


def test_workflow_audit_requires_neutral_resume_planner_guidance(
    tmp_path: Path,
) -> None:
    _write_minimal_workflow_root(tmp_path)
    planner = tmp_path / "scripts/plan_next_resume_brief.sh"
    planner.write_text(
        "#!/usr/bin/env bash\n"
        "printf 'choose slug: bash scripts/plan_next_resume_brief.sh verified-ontology-lock\\n'\n"
        "printf 'bash scripts/validate_resume_brief.sh docs/briefs/007-verified-ontology-lock.md\\n'\n",
        encoding="utf-8",
    )
    planner.chmod(0o755)

    result = _run(
        ["bash", "scripts/audit_autonomous_workflow.sh", str(tmp_path)],
        check=False,
    )

    assert result.returncode == 1
    assert "MISS resume planner uses neutral slug example" in result.stdout
    assert "MISS resume planner avoids no-slug validation target" in result.stdout
    assert "MISS resume planner avoids placeholder next path" in result.stdout
    assert "MISS resume planner shows placeholder path as template" in result.stdout
    assert "MISS resume planner avoids hardcoded resume planner slug" in result.stdout
    assert (
        "MISS resume planner avoids stale hardcoded resume-validation target"
        in result.stdout
    )
    assert "workflow audit warnings:" in result.stdout


def test_workflow_audit_requires_stopped_state_manager_protocol(tmp_path: Path) -> None:
    _write_minimal_workflow_root(tmp_path)
    manager_protocol = tmp_path / "docs/autonomous-workflow/06-manager-guardian-protocol.md"
    manager_protocol.write_text(
        "# Manager\n\nGeneral manager guidance only.\n",
        encoding="utf-8",
    )

    result = _run(
        ["bash", "scripts/audit_autonomous_workflow.sh", str(tmp_path)],
        check=False,
    )

    assert result.returncode == 1
    assert "MISS manager protocol defines stopped-state support" in result.stdout
    assert (
        "MISS manager protocol preserves stopped-state product boundary"
        in result.stdout
    )
    assert "MISS manager protocol requires manager support logs" in result.stdout
    assert (
        "MISS manager protocol separates manager logs from executor/reviewer artifacts"
        in result.stdout
    )
    assert "MISS manager protocol points to latest manager log" in result.stdout
    assert "MISS manager protocol explains manager log template path" in result.stdout
    assert "workflow audit warnings:" in result.stdout


def test_workflow_audit_requires_manager_role_contract_stop_guidance(
    tmp_path: Path,
) -> None:
    _write_minimal_workflow_root(tmp_path)
    role_contracts = tmp_path / "docs/autonomous-workflow/02-role-contracts.md"
    role_contracts.write_text(
        "# Roles\n\n## Manager Contract\n\nGeneral manager guidance only.\n",
        encoding="utf-8",
    )

    result = _run(
        ["bash", "scripts/audit_autonomous_workflow.sh", str(tmp_path)],
        check=False,
    )

    assert result.returncode == 1
    assert "ok   role contracts define manager contract" in result.stdout
    assert (
        "MISS manager role contract preserves stop sentinel boundary"
        in result.stdout
    )
    assert "MISS manager role contract points to latest manager log" in result.stdout
    assert "MISS manager role contract points to manager log planner" in result.stdout
    assert "workflow audit warnings:" in result.stdout


def test_workflow_audit_rejects_stale_scaffold_matrix_state(
    tmp_path: Path,
) -> None:
    _write_minimal_workflow_root(tmp_path)
    matrix = tmp_path / "docs/autonomous-workflow/08-scaffold-adoption-matrix.md"
    matrix.write_text(
        "# 08 Scaffold Adoption Matrix\n\n"
        "| Capability | Status | Notes |\n"
        "|---|---|---|\n"
        "| Active brief | Present | `docs/briefs/001-m0-kg-module-skeleton.md` |\n"
        "| Product implementation | Pending | First executor slice should create the walking skeleton. |\n",
        encoding="utf-8",
    )

    result = _run(
        ["bash", "scripts/audit_autonomous_workflow.sh", str(tmp_path)],
        check=False,
    )

    assert result.returncode == 1
    assert "MISS scaffold matrix names current active brief" in result.stdout
    assert "MISS scaffold matrix preserves stop sentinel state" in result.stdout
    assert "MISS scaffold matrix points to latest manager log" in result.stdout
    assert "MISS scaffold matrix captures completed autonomous plan" in result.stdout
    assert "MISS scaffold matrix avoids stale M0 active brief" in result.stdout
    assert "MISS scaffold matrix avoids stale first-slice pending note" in result.stdout
    assert "workflow audit warnings:" in result.stdout


def test_workflow_audit_requires_workflow_readme_manager_support_guidance(
    tmp_path: Path,
) -> None:
    _write_minimal_workflow_root(tmp_path)
    workflow_readme = tmp_path / "docs/autonomous-workflow/README.md"
    workflow_readme.write_text(
        "# Workflow\n\n"
        "The workflow is complete when the executor leaves a session log and "
        "the reviewer leaves an exact decision.\n",
        encoding="utf-8",
    )

    result = _run(
        ["bash", "scripts/audit_autonomous_workflow.sh", str(tmp_path)],
        check=False,
    )

    assert result.returncode == 1
    assert "ok   workflow README explains executor evidence" in result.stdout
    assert "ok   workflow README explains reviewer evidence" in result.stdout
    assert (
        "MISS workflow README preserves stop sentinel manager boundary"
        in result.stdout
    )
    assert (
        "MISS workflow README points manager turns to latest manager log"
        in result.stdout
    )
    assert "MISS workflow README requires manager support logs" in result.stdout
    assert "MISS workflow README separates manager support evidence" in result.stdout
    assert "workflow audit warnings:" in result.stdout


def test_workflow_audit_requires_operating_model_stopped_state(
    tmp_path: Path,
) -> None:
    _write_minimal_workflow_root(tmp_path)
    operating_model = tmp_path / "docs/autonomous-workflow/01-operating-model.md"
    operating_model.write_text(
        "# Operating\n\n"
        "The workflow uses Executor, Reviewer, and Manager roles.\n",
        encoding="utf-8",
    )

    result = _run(
        ["bash", "scripts/audit_autonomous_workflow.sh", str(tmp_path)],
        check=False,
    )

    assert result.returncode == 1
    assert "MISS operating model defines stopped state" in result.stdout
    assert "MISS operating model preserves stop sentinel boundary" in result.stdout
    assert "MISS operating model stops executor product slices" in result.stdout
    assert (
        "MISS operating model points manager turns to latest manager log"
        in result.stdout
    )
    assert "MISS operating model requires manager support logs" in result.stdout
    assert "workflow audit warnings:" in result.stdout


def test_workflow_audit_requires_execution_protocol_stop_guard(
    tmp_path: Path,
) -> None:
    _write_minimal_workflow_root(tmp_path)
    execution_protocol = tmp_path / "docs/autonomous-workflow/04-execution-protocol.md"
    execution_protocol.write_text(
        "# Execution\n\n"
        "Pick the smallest useful implementation step from the active brief.\n",
        encoding="utf-8",
    )

    result = _run(
        ["bash", "scripts/audit_autonomous_workflow.sh", str(tmp_path)],
        check=False,
    )

    assert result.returncode == 1
    assert "MISS execution protocol starts with agent status" in result.stdout
    assert "MISS execution protocol preserves stop sentinel boundary" in result.stdout
    assert (
        "MISS execution protocol blocks product work while stopped"
        in result.stdout
    )
    assert (
        "MISS execution protocol requires fresh human direction to resume"
        in result.stdout
    )
    assert "workflow audit warnings:" in result.stdout


def test_workflow_audit_requires_manager_log_planner_review_command(
    tmp_path: Path,
) -> None:
    _write_minimal_workflow_root(tmp_path)
    planner = tmp_path / "scripts/plan_next_manager_log.sh"
    planner.write_text(
        "#!/usr/bin/env bash\n"
        "printf 'mode: dry-run (no files written)\\n'\n"
        "printf 'docs/manager-log/000-template-manager-support.md\\n'\n"
        "printf 'latest manager log: docs/manager-log/050-example.md\\n'\n"
        "printf 'Commit with exact paths after rerunning with a concrete slug\\n'\n",
        encoding="utf-8",
    )
    planner.chmod(0o755)

    result = _run(
        ["bash", "scripts/audit_autonomous_workflow.sh", str(tmp_path)],
        check=False,
    )

    assert result.returncode == 1
    assert "ok   manager log planner prints latest manager log path" in result.stdout
    assert "MISS manager log planner prints latest review command" in result.stdout
    assert "MISS manager log planner requires latest log review" in result.stdout
    assert "MISS manager log planner requires diff check" in result.stdout
    assert "MISS manager log planner requires evidence fill" in result.stdout
    assert "workflow audit warnings:" in result.stdout


def test_workflow_audit_rejects_placeholder_manager_next_path(
    tmp_path: Path,
) -> None:
    _write_minimal_workflow_root(tmp_path)
    planner = tmp_path / "scripts/plan_next_manager_log.sh"
    planner.write_text(
        "#!/usr/bin/env bash\n"
        "printf 'mode: dry-run (no files written)\\n'\n"
        "printf 'docs/manager-log/000-template-manager-support.md\\n'\n"
        "printf 'latest manager log: docs/manager-log/050-example.md\\n'\n"
        "printf 'review latest command:\\n'\n"
        "printf 'next manager log: docs/manager-log/051-<support-slug>.md\\n'\n"
        "printf 'Commit with exact paths after rerunning with a concrete slug\\n'\n",
        encoding="utf-8",
    )
    planner.chmod(0o755)

    result = _run(
        ["bash", "scripts/audit_autonomous_workflow.sh", str(tmp_path)],
        check=False,
    )

    assert result.returncode == 1
    assert "MISS manager log planner avoids placeholder next path" in result.stdout
    assert (
        "MISS manager log planner shows placeholder path as template"
        in result.stdout
    )
    assert "workflow audit warnings:" in result.stdout


def test_workflow_audit_requires_status_manager_log_planner_run(
    tmp_path: Path,
) -> None:
    _write_minimal_workflow_root(tmp_path)
    status_script = tmp_path / "scripts/agent_thread_status.sh"
    status_script.write_text(
        "#!/usr/bin/env bash\n"
        "printf 'manager log plan dry run: bash scripts/plan_next_manager_log.sh\\n'\n"
        "printf 'manager support log required: docs/manager-log/NNN-*.md\\n'\n"
        "printf 'resume plan dry run: bash scripts/plan_next_resume_brief.sh\\n'\n"
        "printf 'resume brief validation: "
        "bash scripts/validate_resume_brief.sh <planner-next-brief-path>\\n'\n",
        encoding="utf-8",
    )
    status_script.chmod(0o755)

    result = _run(
        ["bash", "scripts/audit_autonomous_workflow.sh", str(tmp_path)],
        check=False,
    )

    assert result.returncode == 1
    assert "ok   scripts/agent_thread_status.sh points to manager log planner" in result.stdout
    assert "MISS scripts/agent_thread_status.sh runs manager log planner" in result.stdout
    assert (
        "MISS scripts/agent_thread_status.sh reports manager planner status"
        in result.stdout
    )
    assert "workflow audit warnings:" in result.stdout


def test_workflow_audit_requires_manager_log_template_shape(tmp_path: Path) -> None:
    _write_minimal_workflow_root(tmp_path)
    template = tmp_path / "docs/manager-log/000-template-manager-support.md"
    template.write_text(
        "# Incomplete Manager Template\n\n"
        "## Status\n\n"
        "Missing required stopped-state sections.\n",
        encoding="utf-8",
    )

    result = _run(
        ["bash", "scripts/audit_autonomous_workflow.sh", str(tmp_path)],
        check=False,
    )

    assert result.returncode == 1
    assert "ok   docs/manager-log/000-template-manager-support.md" in result.stdout
    assert "ok   manager log template includes status" in result.stdout
    assert "MISS manager log template includes manager action" in result.stdout
    assert "MISS manager log template includes validation evidence" in result.stdout
    assert "MISS manager log template requires validation outcomes" in result.stdout
    assert "MISS manager log template includes guardrail" in result.stdout
    assert "MISS manager log template preserves stopped-state guardrail" in result.stdout
    assert "workflow audit warnings:" in result.stdout


def test_workflow_audit_rejects_latest_manager_log_placeholders(
    tmp_path: Path,
) -> None:
    _write_minimal_workflow_root(tmp_path)
    latest_log = tmp_path / "docs/manager-log/001-placeholder-evidence.md"
    latest_log.write_text(
        "# Manager Log 001 - Placeholder Evidence\n\n"
        "## Status\n\n"
        "Testing unresolved validation evidence.\n\n"
        "## Manager Action\n\n"
        "Left placeholders in place.\n\n"
        "## Validation Evidence\n\n"
        "Pending.\n\n"
        "- `uv run pytest` - outcome.\n\n"
        "## Guardrail\n\n"
        "This is process support only.\n",
        encoding="utf-8",
    )
    _run(["git", "add", "docs/manager-log/001-placeholder-evidence.md"], cwd=tmp_path)

    result = _run(
        ["bash", "scripts/audit_autonomous_workflow.sh", str(tmp_path)],
        check=False,
    )

    assert result.returncode == 1
    assert (
        "latest tracked manager log: docs/manager-log/001-placeholder-evidence.md"
        in result.stdout
    )
    assert "ok   latest tracked manager log includes validation evidence" in result.stdout
    assert (
        "MISS latest tracked manager log avoids pending validation evidence"
        in result.stdout
    )
    assert "MISS latest tracked manager log avoids outcome placeholders" in result.stdout
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
