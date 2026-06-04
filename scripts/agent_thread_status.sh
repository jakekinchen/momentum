#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$PWD}"
ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT"

section() {
  printf '\n== %s ==\n' "$1"
}

resume_brief_example_target() {
  target="$(
    { bash scripts/plan_next_resume_brief.sh verified-ontology-lock 2>/dev/null || true; } |
      awk -F': ' '/^next brief:/ { print $2; exit }'
  )"
  if [ -n "${target:-}" ]; then
    printf '%s\n' "$target"
  else
    printf 'docs/briefs/007-verified-ontology-lock.md\n'
  fi
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
git log --oneline -1

section "Goal Stop State"
if [ -f GOAL.md ]; then
  if grep -q '^[[:space:]]*<stop-orchestrator/>[[:space:]]*$' GOAL.md; then
    printf 'stop sentinel: present\n'
    printf 'executor product slices: stopped until fresh human direction\n'
    printf 'resume plan example: bash scripts/plan_next_resume_brief.sh verified-ontology-lock\n'
    printf 'resume brief validation example: bash scripts/validate_resume_brief.sh %s\n' "$(resume_brief_example_target)"
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
