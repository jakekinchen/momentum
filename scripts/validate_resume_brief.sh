#!/usr/bin/env bash
set -euo pipefail

BRIEF="${1:-}"
ROOT="${2:-${FITGRAPH_ROOT:-$PWD}}"

if [ -z "$BRIEF" ]; then
  printf 'Usage: bash scripts/validate_resume_brief.sh docs/briefs/NNN-slice-name.md [repo-root]\n' >&2
  exit 2
fi

ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT"

warns=0

section() {
  printf '\n== %s ==\n' "$1"
}

ok() {
  printf 'ok   %s\n' "$1"
}

miss() {
  printf 'MISS %s\n' "$1"
  warns=$((warns + 1))
}

require_text() {
  text="$1"
  label="$2"
  if grep -Fq "$text" "$BRIEF"; then
    ok "$label"
  else
    miss "$label"
  fi
}

reject_text() {
  text="$1"
  label="$2"
  if grep -Fq "$text" "$BRIEF"; then
    miss "$label"
  else
    ok "$label"
  fi
}

section "Resume Brief Validation"
printf 'mode: dry-run (no files written)\n'
printf 'root: %s\n' "$ROOT"
printf 'brief: %s\n' "$BRIEF"

case "$BRIEF" in
  docs/briefs/[0-9][0-9][0-9]-*.md)
    ok "brief path is numbered under docs/briefs"
    ;;
  *)
    miss "brief path is numbered under docs/briefs"
    ;;
esac

case "$(basename "$BRIEF")" in
  000-template-*)
    miss "brief is not the 000 template"
    ;;
  *)
    ok "brief is not the 000 template"
    ;;
esac

if [ ! -f "$BRIEF" ]; then
  miss "brief file exists"
  section "Summary"
  printf 'resume brief validation warnings: %s\n' "$warns"
  exit 1
fi
ok "brief file exists"

section "Required Sections"
for heading in \
  "## Human Direction" \
  "## Objective" \
  "## Product / Project Value" \
  "## Acceptance Criteria" \
  "## Expected Files" \
  "## Validation Commands" \
  "## Evidence To Record" \
  "## Reachability / Demo Proof" \
  "## Out Of Scope" \
  "## Stop Conditions" \
  "## Resume Checklist"; do
  require_text "$heading" "$heading"
done

section "Human Direction"
human_direction="$(
  awk '
    /^## Human Direction$/ { in_section = 1; next }
    /^## / && in_section { exit }
    in_section && NF { print }
  ' "$BRIEF"
)"

if [ -n "$human_direction" ] &&
  ! printf '%s\n' "$human_direction" | grep -Fq "Replace this section"; then
  ok "human direction replaced with concrete instruction"
else
  miss "human direction replaced with concrete instruction"
fi

section "Template Placeholders"
reject_text "YYYY-MM-DD" "no template placeholder: YYYY-MM-DD"
reject_text "Replace this section" "no template placeholder: Replace this section"
reject_text "Describe the smallest useful" "no template placeholder: Objective"
reject_text "Explain why this slice matters" "no template placeholder: Product value"
reject_text "List exact files expected to change" "no template placeholder: Expected files"
reject_text "Name the command, API, test, or demo path" "no template placeholder: Reachability"
reject_text "List work that must not be done" "no template placeholder: Out of scope"
reject_text "docs/briefs/007-<slice-name>.md" "no template placeholder: example brief path"

section "Guardrails"
require_text "deterministic graph behavior" "deterministic graph behavior preserved"
require_text "graph/ontology-lock.json" "ontology lock truthfulness preserved"
require_text "MAPS_TO" "MAPS_TO audit metadata preserved"
require_text "vector" "vector safety-enforcement guardrail present"

section "Validation Commands"
require_text "uv run pytest" "pytest command present"
require_text "uv run python -m kg.validation" "KG validation command present"
require_text "bash scripts/audit_autonomous_workflow.sh" "workflow audit command present"
require_text "node scripts/audit_codex_pair_state.mjs" "pair-state audit command present"

section "GOAL State"
if [ -f GOAL.md ]; then
  if grep -Fq "$BRIEF" GOAL.md; then
    printf 'goal current slice: matches candidate brief\n'
  else
    printf 'goal current slice: does not match candidate brief\n'
  fi

  if grep -q '^[[:space:]]*<stop-orchestrator/>[[:space:]]*$' GOAL.md; then
    printf 'stop sentinel: present\n'
  else
    printf 'stop sentinel: absent\n'
  fi
else
  printf 'GOAL.md missing\n'
fi

section "Summary"
if [ "$warns" -eq 0 ]; then
  printf 'resume brief validation clean\n'
else
  printf 'resume brief validation warnings: %s\n' "$warns"
  exit 1
fi
