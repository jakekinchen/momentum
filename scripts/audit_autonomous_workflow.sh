#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$PWD}"
cd "$ROOT"

warns=0

section() {
  printf '\n== %s ==\n' "$1"
}

require_file() {
  if [ -f "$1" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'MISS %s\n' "$1"
    warns=$((warns + 1))
  fi
}

require_executable() {
  require_file "$1"
  if [ -f "$1" ]; then
    if [ -x "$1" ]; then
      printf 'ok   executable %s\n' "$1"
    else
      printf 'MISS executable %s\n' "$1"
      warns=$((warns + 1))
    fi
  fi
}

require_text_in_file() {
  file="$1"
  text="$2"
  label="$3"
  if [ -f "$file" ] && grep -Fq "$text" "$file"; then
    printf 'ok   %s\n' "$label"
  else
    printf 'MISS %s\n' "$label"
    warns=$((warns + 1))
  fi
}

reject_text_in_file() {
  file="$1"
  text="$2"
  label="$3"
  if [ -f "$file" ] && grep -Fq "$text" "$file"; then
    printf 'MISS %s\n' "$label"
    warns=$((warns + 1))
  else
    printf 'ok   %s\n' "$label"
  fi
}

reject_regex_in_file() {
  file="$1"
  pattern="$2"
  label="$3"
  if [ -f "$file" ] && grep -Eq "$pattern" "$file"; then
    printf 'MISS %s\n' "$label"
    warns=$((warns + 1))
  else
    printf 'ok   %s\n' "$label"
  fi
}

latest_file() {
  dir="$1"
  if [ -d "$dir" ]; then
    find "$dir" -maxdepth 1 -type f ! -name '.gitkeep' -print | sort | tail -1
  fi
}

active_brief_from_goal() {
  awk '
    /^## Current Slice[[:space:]]*$/ { in_section = 1; next }
    /^## / && in_section { exit }
    in_section && NF { print; exit }
  ' GOAL.md
}

section "Repo"
printf 'root: %s\n' "$(pwd)"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git status --short --branch
  printf 'head: '
  git log --oneline -1 2>/dev/null || true
else
  printf 'not a git repo\n'
  warns=$((warns + 1))
fi

section "Guidance"
dir="$(pwd)"
while [ "$dir" != "/" ]; do
  if [ -f "$dir/AGENTS.md" ]; then
    printf '%s\n' "$dir/AGENTS.md"
  fi
  dir="$(dirname "$dir")"
done
find . -name AGENTS.md -print 2>/dev/null | sort || true

section "Required workflow files"
require_file "AGENTS.md"
require_file "README.md"
require_file "GOAL.md"
require_file "docs/kg-module-prd.md"
require_file "docs/agent-thread-handoff.md"
require_file "executor-reviewer-pair-programming.md"
require_file "docs/briefs/000-template-human-approved-resume.md"
require_file "docs/manager-log/000-template-manager-support.md"
require_file "docs/autonomous-workflow/README.md"
require_file "docs/autonomous-workflow/01-operating-model.md"
require_file "docs/autonomous-workflow/02-role-contracts.md"
require_file "docs/autonomous-workflow/03-planning-system.md"
require_file "docs/autonomous-workflow/04-execution-protocol.md"
require_file "docs/autonomous-workflow/05-devops-and-session-ops.md"
require_file "docs/autonomous-workflow/06-manager-guardian-protocol.md"
require_file "docs/autonomous-workflow/07-document-and-artifact-map.md"
require_file "docs/autonomous-workflow/08-scaffold-adoption-matrix.md"
require_executable "scripts/agent_thread_status.sh"
require_executable "scripts/audit_autonomous_workflow.sh"
require_file "scripts/audit_codex_pair_state.mjs"
require_text_in_file \
  "scripts/audit_codex_pair_state.mjs" \
  "\${dir} latest:" \
  "pair-state audit labels latest artifacts"
require_executable "scripts/plan_next_manager_log.sh"
require_executable "scripts/plan_next_resume_brief.sh"
require_executable "scripts/validate_resume_brief.sh"
require_executable "scripts/run_codex_pair_cycle.sh"
require_executable "scripts/start_codex_goal_loop.sh"
require_executable "scripts/stop_codex_goal_loop.sh"

section "Entrypoint guidance"
require_text_in_file \
  "AGENTS.md" \
  "bash scripts/agent_thread_status.sh" \
  "AGENTS.md points to agent status"
require_text_in_file \
  "AGENTS.md" \
  "docs/agent-thread-handoff.md" \
  "AGENTS.md points to handoff"
require_text_in_file \
  "AGENTS.md" \
  "<stop-orchestrator/>" \
  "AGENTS.md preserves stop sentinel guidance"
require_text_in_file \
  "AGENTS.md" \
  "bash scripts/plan_next_manager_log.sh" \
  "AGENTS.md points to manager log planner"
require_text_in_file \
  "AGENTS.md" \
  "docs/manager-log/NNN-*.md" \
  "AGENTS.md requires manager support logs"
require_text_in_file \
  "AGENTS.md" \
  "docs/manager-log latest:" \
  "AGENTS.md points manager turns to latest manager log"
require_text_in_file \
  "AGENTS.md" \
  "bash scripts/validate_resume_brief.sh" \
  "AGENTS.md points to resume brief validation"
require_text_in_file \
  "README.md" \
  "bash scripts/agent_thread_status.sh" \
  "README.md points to agent status"
require_text_in_file \
  "README.md" \
  "docs/agent-thread-handoff.md" \
  "README.md points to handoff"
require_text_in_file \
  "README.md" \
  "<stop-orchestrator/>" \
  "README.md preserves stop sentinel guidance"
require_text_in_file \
  "README.md" \
  "bash scripts/plan_next_manager_log.sh" \
  "README.md points to manager log planner"
require_text_in_file \
  "README.md" \
  "docs/manager-log/NNN-*.md" \
  "README.md requires manager support logs"
require_text_in_file \
  "README.md" \
  "docs/manager-log latest:" \
  "README.md points manager turns to latest manager log"
require_text_in_file \
  "README.md" \
  "bash scripts/validate_resume_brief.sh" \
  "README.md points to resume brief validation"
require_text_in_file \
  "docs/agent-thread-handoff.md" \
  "manager-log planner/support-log" \
  "handoff explains audited manager log entrypoint guidance"
require_text_in_file \
  "docs/agent-thread-handoff.md" \
  "manager support log required: docs/manager-log/NNN-*.md" \
  "handoff explains status manager support-log line"
require_text_in_file \
  "docs/agent-thread-handoff.md" \
  "docs/manager-log latest:" \
  "handoff points manager turns to latest manager log"
require_text_in_file \
  "docs/agent-thread-handoff.md" \
  "passes the current collected test suite" \
  "handoff keeps pytest expectation count-neutral"
reject_regex_in_file \
  "docs/agent-thread-handoff.md" \
  "collected [0-9]+ tests" \
  "handoff avoids hardcoded pytest count"
require_text_in_file \
  "docs/autonomous-workflow/05-devops-and-session-ops.md" \
  "manager support log required: docs/manager-log/NNN-*.md" \
  "devops docs explain status manager support-log line"
require_text_in_file \
  "docs/autonomous-workflow/05-devops-and-session-ops.md" \
  "docs/manager-log latest:" \
  "devops docs point manager turns to latest manager log"

section "Static resume targets"
for file in README.md docs/agent-thread-handoff.md docs/autonomous-workflow/05-devops-and-session-ops.md; do
  require_text_in_file \
    "$file" \
    "bash scripts/validate_resume_brief.sh <planner-next-brief-path>" \
    "$file uses planner resume-validation target"
  reject_text_in_file \
    "$file" \
    "bash scripts/validate_resume_brief.sh docs/briefs/007-verified-ontology-lock.md" \
    "$file avoids stale hardcoded resume-validation target"
done

section "Status stopped-state guidance"
require_text_in_file \
  "scripts/agent_thread_status.sh" \
  "manager log plan dry run: bash scripts/plan_next_manager_log.sh" \
  "scripts/agent_thread_status.sh points to manager log planner"
require_text_in_file \
  "scripts/agent_thread_status.sh" \
  "manager support log required: docs/manager-log/NNN-*.md" \
  "scripts/agent_thread_status.sh requires manager support logs"
require_text_in_file \
  "scripts/agent_thread_status.sh" \
  "resume plan dry run: bash scripts/plan_next_resume_brief.sh" \
  "scripts/agent_thread_status.sh uses neutral resume planner dry run"
require_text_in_file \
  "scripts/agent_thread_status.sh" \
  "resume brief validation: bash scripts/validate_resume_brief.sh <planner-next-brief-path>" \
  "scripts/agent_thread_status.sh uses neutral resume-validation target"
reject_text_in_file \
  "scripts/agent_thread_status.sh" \
  "bash scripts/validate_resume_brief.sh docs/briefs/007-verified-ontology-lock.md" \
  "scripts/agent_thread_status.sh avoids stale hardcoded resume-validation target"

section "Manager protocol"
require_text_in_file \
  "docs/autonomous-workflow/06-manager-guardian-protocol.md" \
  "## Stopped-State Manager Support" \
  "manager protocol defines stopped-state support"
require_text_in_file \
  "docs/autonomous-workflow/06-manager-guardian-protocol.md" \
  "Stopped-state support must not start product execution" \
  "manager protocol preserves stopped-state product boundary"
require_text_in_file \
  "docs/autonomous-workflow/06-manager-guardian-protocol.md" \
  "docs/manager-log/NNN-*.md" \
  "manager protocol requires manager support logs"
require_text_in_file \
  "docs/autonomous-workflow/06-manager-guardian-protocol.md" \
  "Manager-only support does not need executor" \
  "manager protocol separates manager logs from executor/reviewer artifacts"
require_text_in_file \
  "docs/autonomous-workflow/06-manager-guardian-protocol.md" \
  "docs/manager-log/000-template-manager-support.md" \
  "manager protocol points to manager log template"

section "Manager log template"
require_text_in_file \
  "docs/manager-log/000-template-manager-support.md" \
  "## Status" \
  "manager log template includes status"
require_text_in_file \
  "docs/manager-log/000-template-manager-support.md" \
  "## Manager Action" \
  "manager log template includes manager action"
require_text_in_file \
  "docs/manager-log/000-template-manager-support.md" \
  "## Validation Evidence" \
  "manager log template includes validation evidence"
require_text_in_file \
  "docs/manager-log/000-template-manager-support.md" \
  "## Guardrail" \
  "manager log template includes guardrail"
require_text_in_file \
  "docs/manager-log/000-template-manager-support.md" \
  "This is process support only" \
  "manager log template preserves stopped-state guardrail"

section "Manager log planner"
require_text_in_file \
  "scripts/plan_next_manager_log.sh" \
  "mode: dry-run (no files written)" \
  "manager log planner is dry run"
require_text_in_file \
  "scripts/plan_next_manager_log.sh" \
  "docs/manager-log/000-template-manager-support.md" \
  "manager log planner uses manager support template"
require_text_in_file \
  "scripts/plan_next_manager_log.sh" \
  "Commit with exact paths after rerunning with a concrete slug" \
  "manager log planner avoids no-slug exact git add paths"
reject_text_in_file \
  "scripts/plan_next_manager_log.sh" \
  "git add docs/manager-log/" \
  "manager log planner avoids placeholder exact git add target"

section "Goal"
if [ -f GOAL.md ]; then
  sed -n '1,100p' GOAL.md
  active_brief="$(active_brief_from_goal || true)"
  if [ -n "${active_brief:-}" ]; then
    printf '\nactive brief: %s\n' "$active_brief"
    require_file "$active_brief"
  else
    printf '\nMISS active brief named in GOAL.md\n'
    warns=$((warns + 1))
  fi
  if grep -q '^[[:space:]]*<stop-orchestrator/>[[:space:]]*$' GOAL.md; then
    printf '\nSTOP SENTINEL PRESENT\n'
    if grep -q 'Refusing to start Codex goal loop' scripts/start_codex_goal_loop.sh 2>/dev/null; then
      printf 'ok   start loop stop guard present\n'
    else
      printf 'MISS start loop stop guard\n'
      warns=$((warns + 1))
    fi
  fi
else
  printf 'GOAL.md missing; create it before autonomous execution.\n'
  warns=$((warns + 1))
fi

section "Milestones"
if [ -f docs/autonomous-workflow/09-fitgraph-autonomous-plan.md ]; then
  grep -n '^## M[0-9]' docs/autonomous-workflow/09-fitgraph-autonomous-plan.md || true
else
  printf 'milestone file missing\n'
  warns=$((warns + 1))
fi

section "Latest workflow artifacts"
for dir in docs/briefs docs/session-logs docs/reviewer-messages docs/manager-log; do
  if [ -d "$dir" ]; then
    latest="$(latest_file "$dir" || true)"
    if [ -n "${latest:-}" ]; then
      printf '%s latest: %s\n' "$dir" "$latest"
    else
      printf '%s latest: none\n' "$dir"
    fi
  else
    printf 'MISS %s\n' "$dir"
    warns=$((warns + 1))
  fi
done

section "Project commands"
if [ -f pyproject.toml ]; then
  printf 'pyproject.toml present\n'
  printf 'agent status: bash scripts/agent_thread_status.sh\n'
  if command -v uv >/dev/null 2>&1; then
    printf 'suggested checks: uv sync && uv run pytest\n'
  else
    printf 'suggested checks: python -m pytest\n'
  fi
else
  printf 'pyproject.toml not present yet\n'
fi

section "Summary"
if [ "$warns" -eq 0 ]; then
  printf 'workflow audit clean\n'
else
  printf 'workflow audit warnings: %s\n' "$warns"
  exit 1
fi
