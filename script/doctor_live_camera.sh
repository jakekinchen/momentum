#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKER="$ROOT_DIR/pose_worker/pose_worker.py"
MODEL="$ROOT_DIR/pose_worker/models/pose_landmarker_lite.task"
MODEL_URL="https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task"
MODE="${1:-check}"

print_step() {
  printf '\n== %s ==\n' "$1"
}

resolve_python_command() {
  if [[ -n "${CAMIFIT_PYTHON:-}" ]]; then
    local configured="${CAMIFIT_PYTHON/#\~/$HOME}"
    if [[ "$configured" == */* || "$configured" == .* ]]; then
      PYTHON_CMD=("$configured")
    else
      [[ "$configured" == "python" ]] && configured="python3"
      PYTHON_CMD=("/usr/bin/env" "$configured")
    fi
    return
  fi

  if [[ -x "$ROOT_DIR/.venv/bin/python" ]]; then
    PYTHON_CMD=("$ROOT_DIR/.venv/bin/python")
    return
  fi

  for candidate in "$HOME/.local/bin/python3.12" /opt/homebrew/bin/python3.12 /usr/local/bin/python3.12 /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
    if [[ -x "$candidate" ]]; then
      PYTHON_CMD=("$candidate")
      return
    fi
  done

  PYTHON_CMD=("/usr/bin/env" "python3")
}

doctor_python_info() {
  "${PYTHON_CMD[@]}" - <<'PY'
import platform
import sys

print(f"executable={sys.executable}")
print(f"version={platform.python_version()}")
print(f"machine={platform.machine()}")
print(f"prefix={sys.prefix}")
ok = (3, 9) <= sys.version_info[:2] <= (3, 12)
print(f"mediapipe_python_supported={str(ok).lower()}")
raise SystemExit(0 if ok else 1)
PY
}

install_with_local_venv() {
  local python_for_venv=""
  for candidate in "$HOME/.local/bin/python3.12" python3.12 /opt/homebrew/bin/python3.12 /usr/local/bin/python3.12; do
    if command -v "$candidate" >/dev/null 2>&1; then
      python_for_venv="$(command -v "$candidate")"
      break
    fi
  done

  if [[ -z "$python_for_venv" && "$(command -v uv || true)" != "" ]]; then
    echo "Python 3.12 not found; asking uv to install/find Python 3.12."
    uv python install 3.12
    python_for_venv="$(uv python find 3.12)"
  fi

  if [[ -z "$python_for_venv" && "$(command -v brew || true)" != "" ]]; then
    echo "Python 3.12 not found; asking Homebrew to install python@3.12."
    brew install python@3.12
    for candidate in /opt/homebrew/bin/python3.12 /usr/local/bin/python3.12; do
      if [[ -x "$candidate" ]]; then
        python_for_venv="$candidate"
        break
      fi
    done
  fi

  if [[ -z "$python_for_venv" ]]; then
    echo "No supported Python 3.12 found." >&2
    echo "Install Python 3.12, then rerun: script/doctor_live_camera.sh --fix" >&2
    echo "Examples: brew install python@3.12  OR  uv python install 3.12" >&2
    exit 1
  fi

  "$python_for_venv" - <<'PY'
import sys
if not ((3, 9) <= sys.version_info[:2] <= (3, 12)):
    raise SystemExit(
        "Selected Python is not supported by MediaPipe. Install Python 3.12 "
        "(for example: brew install python@3.12), then rerun this script."
    )
PY

  "$python_for_venv" -m venv "$ROOT_DIR/.venv"
  "$ROOT_DIR/.venv/bin/python" -m pip install --upgrade pip
  "$ROOT_DIR/.venv/bin/python" -m pip install mediapipe pytest
}

if [[ "$MODE" == "--fix" || "$MODE" == "fix" ]]; then
  print_step "Create/update local Python environment"
  install_with_local_venv
  mkdir -p "$(dirname "$MODEL")"
  print_step "Download MediaPipe pose model"
  curl -L -o "$MODEL" "$MODEL_URL"
fi

print_step "Resolve live worker paths"
resolve_python_command
printf 'repo=%s\n' "$ROOT_DIR"
printf 'python_command=%s\n' "${PYTHON_CMD[*]}"
printf 'worker=%s\n' "$WORKER"
printf 'model=%s\n' "$MODEL"

print_step "Python version and architecture"
if ! doctor_python_info; then
  echo "ERROR: MediaPipe currently requires a supported Python version for this app path." >&2
  echo "Try: brew install python@3.12 && python3.12 -m venv .venv && .venv/bin/python -m pip install mediapipe pytest" >&2
  exit 1
fi

print_step "Worker file"
if [[ ! -f "$WORKER" ]]; then
  echo "ERROR: pose worker script missing: $WORKER" >&2
  exit 1
fi
printf 'ok=true\n'

print_step "MediaPipe import"
if ! "${PYTHON_CMD[@]}" - <<'PY'
try:
    import mediapipe as mp
except Exception as exc:
    print(f"mediapipe_import_ok=false")
    print(f"mediapipe_import_error={exc!r}")
    raise SystemExit(1)
print("mediapipe_import_ok=true")
print(f"mediapipe_version={getattr(mp, '__version__', 'unknown')}")
PY
then
  echo "ERROR: MediaPipe is not importable from the Python command above." >&2
  echo "Fix with: script/doctor_live_camera.sh --fix" >&2
  exit 1
fi

print_step "Pose model"
if [[ ! -f "$MODEL" ]]; then
  echo "ERROR: model missing: $MODEL" >&2
  echo "Fix with: script/doctor_live_camera.sh --fix" >&2
  exit 1
fi
printf 'ok=true bytes=%s\n' "$(wc -c < "$MODEL" | tr -d ' ')"

print_step "Worker health"
STDERR_FILE="$(mktemp)"
set +e
HEALTH_OUTPUT="$(
  printf '{"type":"health"}\n' \
    | "${PYTHON_CMD[@]}" "$WORKER" --mode mediapipe --model "$MODEL" 2>"$STDERR_FILE"
)"
WORKER_STATUS=$?
set -e
WORKER_STDERR="$(tr '\n' ' ' < "$STDERR_FILE" | sed 's/[[:space:]]*$//')"
rm -f "$STDERR_FILE"

if [[ $WORKER_STATUS -ne 0 ]]; then
  echo "ERROR: worker exited with status $WORKER_STATUS" >&2
  [[ -n "$WORKER_STDERR" ]] && echo "stderr=$WORKER_STDERR" >&2
  exit "$WORKER_STATUS"
fi

printf '%s\n' "$HEALTH_OUTPUT"
HEALTH_JSON="$HEALTH_OUTPUT" "${PYTHON_CMD[@]}" - <<'PY'
import json
import os
import sys

payload = os.environ.get("HEALTH_JSON", "").strip().splitlines()
if not payload:
    raise SystemExit("ERROR: worker produced no health response")
health = json.loads(payload[-1])
if not (health.get("ok") and health.get("pose_ready")):
    print(f"ERROR: worker not ready: {health.get('message')}", file=sys.stderr)
    raise SystemExit(1)
print("live_camera_worker_ready=true")
PY

print_step "Done"
echo "Live Camera worker preflight passed."
