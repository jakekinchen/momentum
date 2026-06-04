#!/usr/bin/env bash
set -euo pipefail

SLUG="${1:-<support-slug>}"
ROOT="${2:-${FITGRAPH_ROOT:-$PWD}}"
ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT"

section() {
  printf '\n== %s ==\n' "$1"
}

if [ "$SLUG" != "<support-slug>" ]; then
  case "$SLUG" in
    "" | -* | *- | *[!a-z0-9-]*)
      printf 'Usage: bash scripts/plan_next_manager_log.sh [lowercase-support-slug]\n' >&2
      printf 'Example: bash scripts/plan_next_manager_log.sh manager-log-template\n' >&2
      exit 2
      ;;
  esac
fi

template="docs/manager-log/000-template-manager-support.md"

section "Manager Log Plan"
printf 'mode: dry-run (no files written)\n'
printf 'root: %s\n' "$ROOT"

if [ ! -f "$template" ]; then
  printf 'missing template: %s\n' "$template" >&2
  exit 1
fi

latest_num="$(
  find docs/manager-log -maxdepth 1 -type f -name '[0-9][0-9][0-9]-*.md' ! -name '000-template-*' -exec basename {} \; |
    sed -n 's/^\([0-9][0-9][0-9]\)-.*$/\1/p' |
    sort -n |
    tail -1
)"

if [ -z "${latest_num:-}" ]; then
  latest_num="000"
fi

if [ "$latest_num" = "000" ]; then
  latest_file="none"
else
  latest_file="$(
    find docs/manager-log -maxdepth 1 -type f -name "${latest_num}-*.md" |
      sort |
      tail -1
  )"
fi

next_num="$(printf '%03d' "$((10#$latest_num + 1))")"
if [ "$SLUG" = "<support-slug>" ]; then
  target_template="docs/manager-log/${next_num}-<support-slug>.md"
else
  target="docs/manager-log/${next_num}-${SLUG}.md"
fi

section "Current Guard"
if grep -q '^[[:space:]]*<stop-orchestrator/>[[:space:]]*$' GOAL.md 2>/dev/null; then
  printf 'stop sentinel: present\n'
  printf 'support mode: manager process support only\n'
else
  printf 'stop sentinel: absent\n'
  printf 'support mode: verify GOAL.md and active role before writing manager logs\n'
fi

section "Next Manager Log"
printf 'template: %s\n' "$template"
printf 'latest numbered manager log: %s\n' "$latest_num"
printf 'latest manager log: %s\n' "$latest_file"
if [ "$latest_file" = "none" ]; then
  printf 'review latest command: latest manager log unavailable\n'
else
  printf "review latest command: sed -n '1,160p' %s\n" "$latest_file"
fi

if [ "$SLUG" = "<support-slug>" ]; then
  printf 'next manager log: rerun with a lowercase slug to print exact path\n'
  printf 'next manager log template: %s\n' "$target_template"
  printf 'choose slug: bash scripts/plan_next_manager_log.sh manager-log-template\n'
  printf 'copy command: rerun with a lowercase slug to print an exact copy command\n'
else
  printf 'next manager log: %s\n' "$target"
  printf 'copy command: cp %s %s\n' "$template" "$target"
fi

section "Required Follow-Up"
printf '1. Replace template placeholders with the actual stopped-state support slice.\n'
printf '2. Keep the Guardrail section process-only unless the human explicitly changes roles.\n'
printf '3. Run: uv run pytest\n'
printf '4. Run: uv run python -m kg.validation\n'
printf '5. Run: bash scripts/audit_autonomous_workflow.sh\n'
printf '6. Run: bash scripts/agent_thread_status.sh\n'
printf '7. Run: git diff --check\n'
if [ "$SLUG" = "<support-slug>" ]; then
  printf '8. Commit with exact paths after rerunning with a concrete slug: git add <planner-next-manager-log-path> <changed-support-paths>\n'
else
  printf '8. Commit with exact paths: git add %s <changed-support-paths>\n' "$target"
fi
