#!/usr/bin/env bash
set -euo pipefail

SLUG="${1:-<slice-name>}"
ROOT="${2:-${FITGRAPH_ROOT:-$PWD}}"
ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT"

section() {
  printf '\n== %s ==\n' "$1"
}

if [ "$SLUG" != "<slice-name>" ]; then
  case "$SLUG" in
    "" | -* | *- | *[!a-z0-9-]*)
      printf 'Usage: bash scripts/plan_next_resume_brief.sh [lowercase-slice-slug]\n' >&2
      printf 'Example: bash scripts/plan_next_resume_brief.sh next-slice-slug\n' >&2
      exit 2
      ;;
  esac
fi

template="docs/briefs/000-template-human-approved-resume.md"

section "Resume Brief Plan"
printf 'mode: dry-run (no files written)\n'
printf 'root: %s\n' "$ROOT"

if [ ! -f "$template" ]; then
  printf 'missing template: %s\n' "$template" >&2
  exit 1
fi

latest_num="$(
  find docs/briefs -maxdepth 1 -type f -name '[0-9][0-9][0-9]-*.md' ! -name '000-template-*' -exec basename {} \; |
    sed -n 's/^\([0-9][0-9][0-9]\)-.*$/\1/p' |
    sort -n |
    tail -1
)"

if [ -z "${latest_num:-}" ]; then
  latest_num="000"
fi

next_num="$(printf '%03d' "$((10#$latest_num + 1))")"
if [ "$SLUG" = "<slice-name>" ]; then
  target_template="docs/briefs/${next_num}-<slice-name>.md"
else
  target="docs/briefs/${next_num}-${SLUG}.md"
fi

section "Current Guard"
if grep -q '^[[:space:]]*<stop-orchestrator/>[[:space:]]*$' GOAL.md 2>/dev/null; then
  printf 'stop sentinel: present\n'
  printf 'product work: stopped until fresh human direction updates GOAL.md\n'
else
  printf 'stop sentinel: absent\n'
  printf 'product work: follow GOAL.md and the active brief\n'
fi

section "Next Brief"
printf 'template: %s\n' "$template"
printf 'latest numbered brief: %s\n' "$latest_num"

if [ "$SLUG" = "<slice-name>" ]; then
  printf 'next brief: rerun with a lowercase slug to print exact path\n'
  printf 'next brief template: %s\n' "$target_template"
  printf 'choose slug: bash scripts/plan_next_resume_brief.sh next-slice-slug\n'
  printf 'copy command: rerun with a lowercase slug to print an exact copy command\n'
else
  printf 'next brief: %s\n' "$target"
  printf 'copy command: cp %s %s\n' "$template" "$target"
fi

section "Required Follow-Up"
printf '1. Replace the Human Direction section with the exact user instruction.\n'
if [ "$SLUG" = "<slice-name>" ]; then
  printf '2. Rerun with a lowercase slug to print the exact resume-brief validation command.\n'
  printf '3. Update GOAL.md to point Current Slice at the drafted candidate brief after rerunning with a concrete slug.\n'
else
  printf '2. Run: bash scripts/validate_resume_brief.sh %s\n' "$target"
  printf '3. Update GOAL.md to point Current Slice at %s.\n' "$target"
fi
printf '4. Remove or replace <stop-orchestrator/> only after human approval.\n'
printf '5. Run: bash scripts/agent_thread_status.sh\n'
if [ "$SLUG" = "<slice-name>" ]; then
  printf '6. Commit with exact paths after rerunning with a concrete slug: git add <planner-next-brief-path> GOAL.md\n'
else
  printf '6. Commit with exact paths: git add %s GOAL.md\n' "$target"
fi

section "Validation"
if [ "$SLUG" = "<slice-name>" ]; then
  printf 'bash scripts/validate_resume_brief.sh <planner-next-brief-path>  # after rerunning with a lowercase slug and drafting the candidate brief\n'
else
  printf 'bash scripts/validate_resume_brief.sh %s\n' "$target"
fi
printf 'uv run pytest\n'
printf 'uv run python -m kg.validation\n'
printf 'bash scripts/audit_autonomous_workflow.sh\n'
printf 'node scripts/audit_codex_pair_state.mjs\n'
