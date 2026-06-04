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
git log --oneline -1

section "Goal Stop State"
if [ -f GOAL.md ]; then
  if grep -q '^[[:space:]]*<stop-orchestrator/>[[:space:]]*$' GOAL.md; then
    printf 'stop sentinel: present\n'
    printf 'executor product slices: stopped until fresh human direction\n'
    printf 'resume plan example: bash scripts/plan_next_resume_brief.sh verified-ontology-lock\n'
  else
    printf 'stop sentinel: absent\n'
    printf 'executor product slices: follow GOAL.md and active brief\n'
  fi
else
  printf 'GOAL.md missing\n'
fi

section "Workflow Audit"
bash scripts/audit_autonomous_workflow.sh

section "Pair State Audit"
node scripts/audit_codex_pair_state.mjs
