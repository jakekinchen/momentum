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

require_any_file() {
  label="$1"
  shift
  for candidate in "$@"; do
    if [ -f "$candidate" ]; then
      printf 'ok   %s\n' "$candidate"
      return
    fi
  done
  printf 'MISS %s\n' "$label"
  warns=$((warns + 1))
}

latest_file() {
  dir="$1"
  if [ -d "$dir" ]; then
    find "$dir" -maxdepth 1 -type f ! -name '.gitkeep' -print | sort | tail -1
  fi
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
require_file "executor-reviewer-pair-programming.md"
require_file "docs/autonomous-workflow/README.md"
require_file "docs/autonomous-workflow/01-operating-model.md"
require_file "docs/autonomous-workflow/02-role-contracts.md"
require_file "docs/autonomous-workflow/03-planning-system.md"
require_file "docs/autonomous-workflow/04-execution-protocol.md"
require_file "docs/autonomous-workflow/05-devops-and-session-ops.md"
require_file "docs/autonomous-workflow/06-manager-guardian-protocol.md"
require_file "docs/autonomous-workflow/07-document-and-artifact-map.md"
require_any_file "docs/autonomous-workflow/08-*.md" \
  "docs/autonomous-workflow/08-scaffold-adoption-matrix.md" \
  "docs/autonomous-workflow/08-external-pattern-assessment.md"

section "Goal"
if [ -f GOAL.md ]; then
  sed -n '1,80p' GOAL.md
  if grep -q '<stop-orchestrator/>' GOAL.md; then
    printf '\nSTOP SENTINEL PRESENT\n'
  fi
else
  printf 'GOAL.md missing; create it before autonomous execution.\n'
  warns=$((warns + 1))
fi

section "Milestones"
milestone_file="$(find docs/autonomous-workflow -maxdepth 1 -type f \( -name '*milestone*.md' -o -name '09-*.md' \) | sort | tail -1 || true)"
if [ -n "${milestone_file:-}" ]; then
  printf 'milestone file: %s\n' "$milestone_file"
  grep -n '^## M[0-9]' "$milestone_file" || true
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

section "Codex role sessions"
role_session_dir=".codex-role-sessions"
if [ -d "$role_session_dir" ]; then
  for role in executor reviewer; do
    session_file="$role_session_dir/$role.session"
    if [ -s "$session_file" ]; then
      printf '%s session: %s\n' "$role" "$(cat "$session_file")"
    else
      printf '%s session: none\n' "$role"
    fi
  done
else
  printf 'role session markers: none yet\n'
fi

repo_slug="$(basename "$(pwd)" | tr -cs 'a-zA-Z0-9._-' '-')"
runtime_dir="/tmp/autonomous-project-workflow/$repo_slug"
if [ -d "$runtime_dir" ]; then
  executor_logs="$(find "$runtime_dir" -maxdepth 1 -type f -name '*-executor.jsonl' -print 2>/dev/null | wc -l | tr -d '[:space:]')"
  reviewer_logs="$(find "$runtime_dir" -maxdepth 1 -type f -name '*-reviewer.jsonl' -print 2>/dev/null | wc -l | tr -d '[:space:]')"
  printf 'runtime logs: %s executor, %s reviewer in %s\n' "$executor_logs" "$reviewer_logs" "$runtime_dir"
else
  printf 'runtime logs: none in %s\n' "$runtime_dir"
fi

section "Project commands"
if [ -f pyproject.toml ]; then
  printf 'pyproject.toml present\n'
  if command -v uv >/dev/null 2>&1; then
    printf 'suggested checks: uv sync && uv run pytest\n'
  else
    printf 'uv not found on PATH\n'
  fi
else
  printf 'pyproject.toml not present yet\n'
fi

section "Summary"
if [ "$warns" -eq 0 ]; then
  printf 'workflow audit clean\n'
else
  printf 'workflow audit warnings: %s\n' "$warns"
fi
