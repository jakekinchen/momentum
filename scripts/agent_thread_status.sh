#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$PWD}"
ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT"

section() {
  printf '\n== %s ==\n' "$1"
}

section "Agent Thread Handoff"
if [ -f docs/agent-thread-handoff.md ]; then
  printf 'handoff: docs/agent-thread-handoff.md\n'
  awk '/^## Start Here/ { exit } { print }' docs/agent-thread-handoff.md
else
  printf 'handoff missing: docs/agent-thread-handoff.md\n'
fi

section "Git"
git status --short --branch
printf 'head: '
git log --oneline -1 2>/dev/null || true

section "Goal Stop State"
if [ -f GOAL.md ]; then
  if grep -q '^[[:space:]]*<stop-orchestrator/>[[:space:]]*$' GOAL.md; then
    printf 'stop sentinel: present\n'
    printf 'executor product slices: stopped until fresh human direction\n'
    printf 'manager log plan dry run: bash scripts/plan_next_manager_log.sh\n'
    printf 'resume plan dry run: bash scripts/plan_next_resume_brief.sh\n'
    printf 'resume plan slug example: bash scripts/plan_next_resume_brief.sh verified-ontology-lock\n'
    printf 'resume brief validation: bash scripts/validate_resume_brief.sh <planner-next-brief-path>\n'
  else
    printf 'stop sentinel: absent\n'
    printf 'executor product slices: follow GOAL.md and active brief\n'
  fi
else
  printf 'GOAL.md missing\n'
fi

section "Workflow Audit"
workflow_status=0
bash scripts/audit_autonomous_workflow.sh || workflow_status=$?

section "Pair State Audit"
pair_status=0
node scripts/audit_codex_pair_state.mjs || pair_status=$?

section "Agent Status Summary"
if [ "$workflow_status" -eq 0 ] && [ "$pair_status" -eq 0 ]; then
  printf 'agent thread status clean\n'
else
  printf 'agent thread status warnings: workflow=%s pair=%s\n' "$workflow_status" "$pair_status"
  exit 1
fi
