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
  # Decide the audit tier before anything below creates dist/ output dirs:
  # source-chain capture folders only exist on local/release machines.
  strict_motion_audit=0
  if [[ -d "$ROOT/dist/motion-reference/bodyweight_pushup" ]]; then
    strict_motion_audit=1
  fi
  # Compile-check and run every motion-reference module and test suite so new
  # tooling cannot be silently skipped by a stale hardcoded list.
  python3 -m py_compile scripts/motion_reference/*.py
  scripts/motion_reference/report_motion_pipeline_gaps.py
  for test_suite in scripts/motion_reference/test_*.py; do
    echo "-- $test_suite"
    python3 "$test_suite"
  done
  if [[ "$strict_motion_audit" == "1" ]]; then
    # Local/release machines hold the dist/ source-chain artifacts; run the
    # full strict provenance tier.
    scripts/motion_reference/audit_motion_coverage.py --strict --require-trackable-reference-clips --require-guide-ready-inventory
  else
    # Fresh clones (CI) cannot verify local-only dist/ artifacts; run the
    # non-strict tier (still includes packaging-gate consistency).
    echo "dist/ source-chain artifacts absent; running non-strict motion audit"
    scripts/motion_reference/audit_motion_coverage.py
  fi
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
