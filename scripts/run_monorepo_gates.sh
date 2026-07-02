#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export UV_CACHE_DIR="${UV_CACHE_DIR:-/private/tmp/camifit-uv-cache}"

echo "== kg-python =="
(
  cd "$ROOT/kg-canonical"
  uv run python -m pytest
)

echo "== kg-validation =="
(
  cd "$ROOT/kg-canonical"
  uv run python -m kg.validation
)

echo "== assessment-import =="
(
  cd "$ROOT/kg-canonical"
  uv run python -m kg.assessment_import
)

echo "== artifact-build =="
(
  cd "$ROOT"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  paths=(
    "Sources/KGKit/Resources/Artifact"
    "Tests/KGKitTests/Fixtures/conformance"
    "kg-canonical/graph/generated"
  )
  for path in "${paths[@]}"; do
    if [[ -e "$path" ]]; then
      mkdir -p "$tmp/before/$(dirname "$path")"
      cp -R "$path" "$tmp/before/$path"
    fi
  done

  FITGRAPH="$ROOT/kg-canonical" python3 scripts/gen_kg_conformance_vectors.py

  for path in "${paths[@]}"; do
    before="$tmp/before/$path"
    after="$ROOT/$path"
    if [[ -e "$before" || -e "$after" ]]; then
      diff -ruN "$before" "$after"
    fi
  done
)

echo "== conformance-parity =="
(
  cd "$ROOT"
  swift test --filter ConformanceTests
)

echo "== swift-test =="
(
  cd "$ROOT"
  swift test
)

echo "== motion-reference-coverage =="
(
  cd "$ROOT"
  python3 -m py_compile \
    scripts/motion_reference/audit_motion_coverage.py \
    scripts/motion_reference/audit_kg_motion_readiness.py \
    scripts/motion_reference/report_motion_pipeline_gaps.py \
    scripts/motion_reference/compile_archetype_trace.py \
    scripts/motion_reference/test_audit_motion_coverage.py \
    scripts/motion_reference/test_report_motion_pipeline_gaps.py \
    scripts/motion_reference/test_compile_archetype_trace.py
  scripts/motion_reference/report_motion_pipeline_gaps.py
  python3 scripts/motion_reference/test_audit_motion_coverage.py
  python3 scripts/motion_reference/test_report_motion_pipeline_gaps.py
  python3 scripts/motion_reference/test_compile_archetype_trace.py
  scripts/motion_reference/audit_motion_coverage.py --strict --require-trackable-reference-clips --require-guide-ready-inventory
)

echo "== kg-motion-readiness =="
(
  cd "$ROOT"
  scripts/motion_reference/audit_kg_motion_readiness.py --summary-only
)

if [[ -d "$ROOT/contracts" ]]; then
  echo "== contracts-compat =="
  find "$ROOT/contracts" -name '*.schema.json' -print | sort
else
  echo "== contracts-compat =="
  echo "contracts/ not present yet; schema compatibility gate is pending the contracts slice."
fi
