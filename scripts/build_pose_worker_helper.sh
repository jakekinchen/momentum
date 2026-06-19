#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="${CAMIFIT_POSE_WORKER_BUILD_PYTHON:-$ROOT_DIR/.venv/bin/python}"
HELPER_NAME="camifit-pose-worker"
BUILD_DIR="$ROOT_DIR/build/pose-worker-pyinstaller"
DIST_DIR="$ROOT_DIR/dist/pose-worker-pyinstaller"
MODEL_PATH="$ROOT_DIR/pose_worker/models/pose_landmarker_lite.task"
WORKER_SCRIPT="$ROOT_DIR/pose_worker/pose_worker.py"
HELPER_EXE="$DIST_DIR/$HELPER_NAME/$HELPER_NAME"

if [[ ! -x "$PYTHON" ]]; then
  echo "ERROR: pose worker helper build requires Python at $PYTHON" >&2
  exit 1
fi

if [[ ! -f "$MODEL_PATH" ]]; then
  echo "ERROR: MediaPipe model missing: $MODEL_PATH" >&2
  exit 1
fi

if ! "$PYTHON" -m PyInstaller --version >/dev/null 2>&1; then
  echo "ERROR: PyInstaller is not installed in $PYTHON" >&2
  echo "ERROR: run '$PYTHON -m pip install pyinstaller' before direct release." >&2
  exit 1
fi

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

"$PYTHON" -m PyInstaller \
  --clean \
  --noconfirm \
  --onedir \
  --name "$HELPER_NAME" \
  --distpath "$DIST_DIR" \
  --workpath "$BUILD_DIR" \
  --specpath "$BUILD_DIR" \
  --runtime-hook "$ROOT_DIR/scripts/pyinstaller_mediapipe_runtime_hook.py" \
  --collect-binaries mediapipe \
  --collect-data mediapipe \
  --hidden-import mediapipe.tasks.c \
  --hidden-import mediapipe.tasks.python.vision.pose_landmarker \
  --hidden-import mediapipe.tasks.python.vision.core.vision_task_running_mode \
  --exclude-module cv2 \
  --exclude-module matplotlib \
  --exclude-module PIL \
  "$WORKER_SCRIPT"

if [[ ! -x "$HELPER_EXE" ]]; then
  echo "ERROR: PyInstaller helper missing after build: $HELPER_EXE" >&2
  exit 1
fi

health="$(printf '{"type":"health"}\n' | "$HELPER_EXE" --mode mediapipe --model "$MODEL_PATH")"
if [[ "$health" != *'"pose_ready":true'* ]]; then
  echo "ERROR: packaged pose worker health check failed:" >&2
  echo "$health" >&2
  exit 1
fi

echo "$DIST_DIR/$HELPER_NAME"
