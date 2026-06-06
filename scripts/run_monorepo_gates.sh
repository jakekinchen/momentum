#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export UV_CACHE_DIR="${UV_CACHE_DIR:-/private/tmp/camifit-uv-cache}"

echo "== kg-python =="
(
  cd "$ROOT/kg-canonical"
  uv run pytest
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
  FITGRAPH="$ROOT/kg-canonical" python3 scripts/gen_kg_conformance_vectors.py
  git diff --exit-code -- \
    Sources/KGKit/Resources/Artifact \
    Tests/KGKitTests/Fixtures/conformance \
    kg-canonical/graph/generated
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
  scripts/motion_reference/audit_motion_coverage.py --strict
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
