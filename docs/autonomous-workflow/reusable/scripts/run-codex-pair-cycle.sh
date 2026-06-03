#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run-codex-pair-cycle.sh --once [options]
  run-codex-pair-cycle.sh --loop [options]
  run-codex-pair-cycle.sh --dry-run [options]
  run-codex-pair-cycle.sh --seed-role-sessions [options]

Options:
  --root <dir>          Target repo. Default: current directory.
  --interval <seconds>  Delay between loop cycles. Default: 60.
  --max-cycles <n>      Maximum loop cycles. Default: 1 for --once, 10 for --loop.
  --model <name>        Pass a model to codex exec.
  --sandbox <mode>      Codex sandbox mode. Default: workspace-write.
  --approval <policy>   Codex approval policy. Default: never.
  --allow-dirty         Allow starting from a dirty worktree.
  --dangerous           Use --dangerously-bypass-approvals-and-sandbox.
  --reset-role-sessions Remove saved Executor/Reviewer session markers and start fresh.
  -h, --help            Show this help.

The loop continues only when the Reviewer writes a latest decision of CONTINUE.
Any STOP, ESCALATE, REDIRECT, NUDGE, missing decision, command failure, or stop
sentinel ends the loop.

By default, the runner persists one Codex thread per role under
.codex-role-sessions/ and resumes those threads on later cycles. If no marker
exists, it seeds the marker from the latest matching JSONL runtime log before
creating a new thread.
EOF
}

ROOT="$PWD"
MODE=""
INTERVAL="60"
MAX_CYCLES=""
MODEL=""
SANDBOX="workspace-write"
APPROVAL="never"
ALLOW_DIRTY=0
DANGEROUS=0
RESET_ROLE_SESSIONS=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --once)
      MODE="once"
      shift
      ;;
    --loop)
      MODE="loop"
      shift
      ;;
    --dry-run)
      MODE="dry-run"
      shift
      ;;
    --seed-role-sessions)
      MODE="seed-role-sessions"
      shift
      ;;
    --root)
      ROOT="${2:?--root requires a directory}"
      shift 2
      ;;
    --interval)
      INTERVAL="${2:?--interval requires seconds}"
      shift 2
      ;;
    --max-cycles)
      MAX_CYCLES="${2:?--max-cycles requires a number}"
      shift 2
      ;;
    --model)
      MODEL="${2:?--model requires a value}"
      shift 2
      ;;
    --sandbox)
      SANDBOX="${2:?--sandbox requires a value}"
      shift 2
      ;;
    --approval)
      APPROVAL="${2:?--approval requires a value}"
      shift 2
      ;;
    --allow-dirty)
      ALLOW_DIRTY=1
      shift
      ;;
    --dangerous)
      DANGEROUS=1
      shift
      ;;
    --reset-role-sessions)
      RESET_ROLE_SESSIONS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$MODE" ]; then
  usage >&2
  exit 2
fi

if [ "$MODE" = "once" ] || [ "$MODE" = "dry-run" ] || [ "$MODE" = "seed-role-sessions" ]; then
  MAX_CYCLES="${MAX_CYCLES:-1}"
else
  MAX_CYCLES="${MAX_CYCLES:-10}"
fi

ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'Not a git repo: %s\n' "$ROOT" >&2
  exit 1
fi

if [ ! -f GOAL.md ]; then
  printf 'GOAL.md missing. Run bootstrap and fill GOAL.md before starting the loop.\n' >&2
  exit 1
fi

if [ ! -f executor-reviewer-pair-programming.md ]; then
  printf 'executor-reviewer-pair-programming.md missing. Run bootstrap before starting the loop.\n' >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1 && [ "$MODE" != "dry-run" ]; then
  printf 'codex CLI not found on PATH.\n' >&2
  exit 1
fi

repo_slug="$(basename "$ROOT" | tr -cs 'a-zA-Z0-9._-' '-')"
runtime_dir="/tmp/autonomous-project-workflow/$repo_slug"
mkdir -p "$runtime_dir"
role_session_dir="$ROOT/.codex-role-sessions"
mkdir -p "$role_session_dir"

lock_dir="$ROOT/.autonomous-workflow.lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  printf 'Another autonomous workflow cycle appears to be running: %s\n' "$lock_dir" >&2
  exit 1
fi
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT

has_stop_sentinel() {
  grep -q '<stop-orchestrator/>' GOAL.md 2>/dev/null
}

latest_file() {
  dir="$1"
  if [ -d "$dir" ]; then
    find "$dir" -maxdepth 1 -type f ! -name '.gitkeep' -print | sort | tail -1
  fi
}

latest_reviewer_decision() {
  file="$(latest_file docs/reviewer-messages || true)"
  if [ -z "${file:-}" ]; then
    return 1
  fi
  sed -n '/^## Decision/,/^## /p' "$file" |
    grep -E '^[[:space:]]*`(CONTINUE|NUDGE|REDIRECT|STOP|ESCALATE)`[[:space:]]*$' |
    head -1 |
    tr -d '`[:space:]'
}

role_session_file() {
  role="$1"
  printf '%s/%s.session\n' "$role_session_dir" "$role"
}

extract_thread_id() {
  file="$1"
  if [ -f "$file" ]; then
    sed -n 's/.*"type":"thread.started","thread_id":"\([^"]*\)".*/\1/p' "$file" | head -1
  fi
}

latest_role_log() {
  role="$1"
  find "$runtime_dir" -maxdepth 1 -type f -name "*-$role.jsonl" -print 2>/dev/null | sort | tail -1
}

seed_role_session_from_logs() {
  role="$1"
  force="${2:-0}"
  session_file="$(role_session_file "$role")"
  if [ "$force" -ne 1 ] && [ -s "$session_file" ]; then
    printf '%s role session already set: %s\n' "$role" "$(cat "$session_file")"
    return 0
  fi

  log_file="$(latest_role_log "$role" || true)"
  if [ -z "${log_file:-}" ]; then
    printf '%s role session not seeded: no prior %s logs in %s\n' "$role" "$role" "$runtime_dir"
    return 1
  fi

  thread_id="$(extract_thread_id "$log_file" || true)"
  if [ -z "${thread_id:-}" ]; then
    printf '%s role session not seeded: no thread.started id in %s\n' "$role" "$log_file"
    return 1
  fi

  printf '%s\n' "$thread_id" > "$session_file"
  printf '%s role session seeded from %s: %s\n' "$role" "$log_file" "$thread_id"
}

seed_all_role_sessions() {
  force="${1:-0}"
  seed_role_session_from_logs executor "$force" || true
  seed_role_session_from_logs reviewer "$force" || true
}

print_role_sessions() {
  for role in executor reviewer; do
    session_file="$(role_session_file "$role")"
    if [ -s "$session_file" ]; then
      printf '%s role session: %s\n' "$role" "$(cat "$session_file")"
    else
      printf '%s role session: none\n' "$role"
    fi
  done
}

ensure_clean_start() {
  if [ "$ALLOW_DIRTY" -eq 1 ]; then
    return
  fi
  if [ -n "$(git status --porcelain)" ]; then
    printf 'Refusing to start from a dirty worktree. Commit/stash changes or pass --allow-dirty.\n' >&2
    git status --short >&2
    exit 1
  fi
}

codex_new_session_args() {
  printf '%s\n' "exec"
  printf '%s\n' "--json"
  printf '%s\n' "-C"
  printf '%s\n' "$ROOT"
  if [ -n "$MODEL" ]; then
    printf '%s\n' "-m"
    printf '%s\n' "$MODEL"
  fi
  if [ "$DANGEROUS" -eq 1 ]; then
    printf '%s\n' "--dangerously-bypass-approvals-and-sandbox"
  else
    printf '%s\n' "-s"
    printf '%s\n' "$SANDBOX"
    printf '%s\n' "-a"
    printf '%s\n' "$APPROVAL"
  fi
}

codex_resume_session_args() {
  session_id="$1"
  printf '%s\n' "exec"
  printf '%s\n' "resume"
  printf '%s\n' "--json"
  if [ -n "$MODEL" ]; then
    printf '%s\n' "-m"
    printf '%s\n' "$MODEL"
  fi
  if [ "$DANGEROUS" -eq 1 ]; then
    printf '%s\n' "--dangerously-bypass-approvals-and-sandbox"
  fi
  printf '%s\n' "$session_id"
}

run_role() {
  role="$1"
  prompt_file="$2"
  stamp="$(date +%Y%m%d%H%M%S)"
  json_log="$runtime_dir/$stamp-$role.jsonl"
  last_msg="$runtime_dir/$stamp-$role-last-message.md"
  session_file="$(role_session_file "$role")"

  if [ "$MODE" = "dry-run" ]; then
    printf '\n[dry-run] would run %s role\n' "$role"
    printf '[dry-run] prompt: %s\n' "$prompt_file"
    printf '[dry-run] log: %s\n' "$json_log"
    if [ -s "$session_file" ]; then
      printf '[dry-run] would resume %s session: %s\n' "$role" "$(cat "$session_file")"
    else
      latest_log="$(latest_role_log "$role" || true)"
      latest_thread_id=""
      if [ -n "${latest_log:-}" ]; then
        latest_thread_id="$(extract_thread_id "$latest_log" || true)"
      fi
      if [ -n "${latest_thread_id:-}" ]; then
        printf '[dry-run] would seed and resume %s session from %s: %s\n' "$role" "$latest_log" "$latest_thread_id"
      else
        printf '[dry-run] would create first %s session and save its id\n' "$role"
      fi
    fi
    return
  fi

  if [ ! -s "$session_file" ] && [ "$RESET_ROLE_SESSIONS" -eq 0 ]; then
    seed_role_session_from_logs "$role" || true
  fi

  args=()
  if [ -s "$session_file" ]; then
    session_id="$(cat "$session_file")"
    while IFS= read -r arg; do
      args+=("$arg")
    done < <(codex_resume_session_args "$session_id")
    printf '\n== Running %s ==\n' "$role"
    printf 'mode: resume session %s\n' "$session_id"
  else
    while IFS= read -r arg; do
      args+=("$arg")
    done < <(codex_new_session_args)
    printf '\n== Running %s ==\n' "$role"
    printf 'mode: new session\n'
  fi
  args+=("-o" "$last_msg" "-")

  printf 'log: %s\n' "$json_log"
  if ! codex "${args[@]}" < "$prompt_file" > "$json_log" 2>&1; then
    printf '%s role failed. See %s\n' "$role" "$json_log" >&2
    if [ -s "$session_file" ]; then
      printf 'Session marker was preserved at %s. Use --reset-role-sessions only if this session is intentionally obsolete.\n' "$session_file" >&2
    fi
    return 1
  fi
  thread_id="$(extract_thread_id "$json_log" || true)"
  if [ -n "${thread_id:-}" ]; then
    printf '%s\n' "$thread_id" > "$session_file"
    printf '%s session marker: %s\n' "$role" "$thread_id"
  elif [ -s "$session_file" ]; then
    printf '%s session marker unchanged: %s\n' "$role" "$(cat "$session_file")"
  else
    printf '%s role completed but no thread.started id was found in %s\n' "$role" "$json_log" >&2
  fi
  printf '%s last message: %s\n' "$role" "$last_msg"
}

write_executor_prompt() {
  out="$1"
  cat > "$out" <<'EOF'
You are the Executor in a repo-local autonomous workflow.

Read and follow:
- executor-reviewer-pair-programming.md
- GOAL.md
- docs/autonomous-workflow/
- latest docs/briefs/NNN-*.md

Your job:
1. If GOAL.md contains <stop-orchestrator/>, do not implement. Report that execution is stopped.
2. Otherwise implement exactly one smallest useful slice from the active brief.
3. Run focused and broad validation appropriate to the slice.
4. Prove reachability from a real product path.
5. Write docs/session-logs/NNN-executor-*.md with files changed, validation, reachability, evidence, flags for Reviewer, and next suggested slice.
6. Commit only scoped files with explicit git add paths. Do not push.

If blocked, write a session log explaining the blocker category, evidence, and smallest next action. Do not wait for user input inside this unattended turn.
EOF
}

write_reviewer_prompt() {
  out="$1"
  cat > "$out" <<'EOF'
You are the Reviewer / Planner in a repo-local autonomous workflow.

Read and follow:
- executor-reviewer-pair-programming.md
- GOAL.md
- docs/autonomous-workflow/
- latest docs/briefs/NNN-*.md
- latest docs/session-logs/NNN-executor-*.md
- latest commit and git diff/status

Your job:
1. Audit the Executor's latest slice from repo evidence.
2. Choose exactly one decision: CONTINUE, NUDGE, REDIRECT, STOP, or ESCALATE.
3. Include an evidence anchor for any NUDGE, REDIRECT, STOP, or ESCALATE.
4. Write docs/reviewer-messages/NNN-*.md.
5. If the decision is CONTINUE, write the next docs/briefs/NNN-*.md and update GOAL.md Current Slice if needed.
6. If the decision is STOP, add <stop-orchestrator/> near the top of GOAL.md.
7. Commit only scoped reviewer/planning docs with an appropriate docs: commit. Do not push.

Do not write product code. If a human decision is required, choose ESCALATE and make the reason concrete.
EOF
}

if [ "$RESET_ROLE_SESSIONS" -eq 1 ]; then
  rm -f "$(role_session_file executor)" "$(role_session_file reviewer)"
  printf 'Removed saved role session markers from %s\n' "$role_session_dir"
fi

if [ "$MODE" = "seed-role-sessions" ]; then
  seed_all_role_sessions 1
  print_role_sessions
  exit 0
fi

if [ "$MODE" != "dry-run" ]; then
  ensure_clean_start
fi

cycle=1
while [ "$cycle" -le "$MAX_CYCLES" ]; do
  printf '\n== Pair cycle %s/%s ==\n' "$cycle" "$MAX_CYCLES"

  if has_stop_sentinel; then
    printf 'Stop sentinel present in GOAL.md. No Executor turn will run.\n'
    exit 0
  fi

  prompt_dir="$(mktemp -d -t autonomous-workflow-prompts-XXXXXX)"
  executor_prompt="$prompt_dir/executor.md"
  reviewer_prompt="$prompt_dir/reviewer.md"
  write_executor_prompt "$executor_prompt"
  write_reviewer_prompt "$reviewer_prompt"

  run_role "executor" "$executor_prompt"
  run_role "reviewer" "$reviewer_prompt"

  rm -rf "$prompt_dir"

  if [ "$MODE" != "loop" ]; then
    break
  fi

  decision="$(latest_reviewer_decision || true)"
  printf 'latest reviewer decision: %s\n' "${decision:-none}"
  if [ "$decision" != "CONTINUE" ]; then
    printf 'Loop stopping because decision is not CONTINUE.\n'
    break
  fi

  if has_stop_sentinel; then
    printf 'Loop stopping because stop sentinel is present.\n'
    break
  fi

  cycle=$((cycle + 1))
  if [ "$cycle" -le "$MAX_CYCLES" ]; then
    sleep "$INTERVAL"
  fi
done

printf '\nPair cycle runner finished.\n'
