#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/dist/releases"
REPO="${MOMENTUM_GITHUB_RELEASE_REPO:-${CAMIFIT_GITHUB_RELEASE_REPO:-jakekinchen/momentum}}"
VERSION="${MOMENTUM_RELEASE_VERSION:-${CAMIFIT_RELEASE_VERSION:-}}"

if [[ -z "$VERSION" ]]; then
  latest_artifact="$(
    find "$RELEASE_DIR" -maxdepth 1 -type f -name 'Momentum-macOS-*.dmg' ! -name 'notary-*' -print0 2>/dev/null \
      | while IFS= read -r -d '' artifact_path; do
          printf '%s\t%s\n' "$(stat -f '%m' "$artifact_path")" "$artifact_path"
        done \
      | sort -rn \
      | sed -n '1s/^[^	]*	//p'
  )"
  if [[ -z "$latest_artifact" ]]; then
    echo "ERROR: set MOMENTUM_RELEASE_VERSION or build a dist/releases/Momentum-macOS-<version>.dmg first." >&2
    exit 1
  fi
  VERSION="$(basename "$latest_artifact")"
  VERSION="${VERSION#Momentum-macOS-}"
  VERSION="${VERSION%.*}"
fi

ARTIFACT="${MOMENTUM_RELEASE_ARTIFACT:-${MOMENTUM_RELEASE_FILE:-${CAMIFIT_RELEASE_ARTIFACT:-${CAMIFIT_RELEASE_FILE:-}}}}"
if [[ -z "$ARTIFACT" ]]; then
  ARTIFACT="$RELEASE_DIR/Momentum-macOS-$VERSION.dmg"
fi
EXTENSION="${MOMENTUM_RELEASE_EXTENSION:-${CAMIFIT_RELEASE_EXTENSION:-${ARTIFACT##*.}}}"
TAG="${MOMENTUM_GITHUB_RELEASE_TAG:-${CAMIFIT_GITHUB_RELEASE_TAG:-macos-$VERSION}}"
TITLE="${MOMENTUM_GITHUB_RELEASE_TITLE:-${CAMIFIT_GITHUB_RELEASE_TITLE:-Momentum macOS $VERSION}}"
STABLE_ASSET_NAME="${MOMENTUM_STABLE_ASSET_NAME:-${CAMIFIT_STABLE_ASSET_NAME:-Momentum-macOS.dmg}}"
VERSIONED_ASSET_NAME="${MOMENTUM_VERSIONED_ASSET_NAME:-${CAMIFIT_VERSIONED_ASSET_NAME:-$(basename "$ARTIFACT")}}"
DOWNLOAD_URL="${MOMENTUM_DOWNLOAD_URL_OVERRIDE:-${CAMIFIT_DOWNLOAD_URL_OVERRIDE:-https://github.com/$REPO/releases/latest/download/$STABLE_ASSET_NAME}}"
WEBSITE_DIR="${MOMENTUM_WEBSITE_DIR:-${CAMIFIT_WEBSITE_DIR:-$ROOT_DIR/website}}"

if [[ ! -f "$ARTIFACT" ]]; then
  echo "ERROR: release artifact not found: $ARTIFACT" >&2
  exit 1
fi
if [[ "$EXTENSION" != "dmg" ]]; then
  echo "ERROR: public direct-download releases must publish a DMG, got: $ARTIFACT" >&2
  exit 1
fi
if [[ "$STABLE_ASSET_NAME" != "Momentum-macOS.dmg" ]]; then
  echo "ERROR: stable public release asset must be Momentum-macOS.dmg, got: $STABLE_ASSET_NAME" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: GitHub CLI is required for GitHub release publishing." >&2
  exit 1
fi

sha="$(shasum -a 256 "$ARTIFACT" | awk '{print $1}')"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
stable_asset="$tmp_dir/$STABLE_ASSET_NAME"
versioned_asset="$tmp_dir/$VERSIONED_ASSET_NAME"
cp "$ARTIFACT" "$stable_asset"
cp "$ARTIFACT" "$versioned_asset"

notes="${MOMENTUM_GITHUB_RELEASE_NOTES:-${CAMIFIT_GITHUB_RELEASE_NOTES:-Notarized direct-download macOS $EXTENSION build. SHA-256: $sha. GitHub Releases is the large-file download path when Supabase Free Storage object limits are too small for bundled builds.}}"

create_release() {
  echo "Creating GitHub release $REPO@$TAG"
    gh release create "$TAG" "$stable_asset" "$versioned_asset" \
    --repo "$REPO" \
    --target "${MOMENTUM_GITHUB_RELEASE_TARGET:-${CAMIFIT_GITHUB_RELEASE_TARGET:-main}}" \
    --title "$TITLE" \
    --notes "$notes" \
    --latest
}

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  if [[ "${MOMENTUM_GITHUB_RECREATE_RELEASE:-${CAMIFIT_GITHUB_RECREATE_RELEASE:-0}}" == "1" ]]; then
    echo "Recreating GitHub release $REPO@$TAG"
    gh release delete "$TAG" --repo "$REPO" --cleanup-tag --yes
    create_release
  else
    echo "GitHub release $REPO@$TAG already exists; leaving assets untouched."
    gh release edit "$TAG" --repo "$REPO" --title "$TITLE" --notes "$notes" --latest
  fi
else
  create_release
fi

verify_artifact="$tmp_dir/downloaded-$STABLE_ASSET_NAME"
curl -fL --retry 8 --retry-delay 3 --retry-all-errors -o "$verify_artifact" "$DOWNLOAD_URL"
downloaded_sha="$(shasum -a 256 "$verify_artifact" | awk '{print $1}')"
if [[ "$downloaded_sha" != "$sha" ]]; then
  echo "ERROR: downloaded GitHub asset SHA mismatch." >&2
  echo "expected=$sha" >&2
  echo "actual=$downloaded_sha" >&2
  exit 1
fi
echo "verified github_download_url=$DOWNLOAD_URL sha256=$sha"

if [[ "${MOMENTUM_UPDATE_VERCEL_DOWNLOAD_URL:-${CAMIFIT_UPDATE_VERCEL_DOWNLOAD_URL:-0}}" == "1" ]]; then
  if ! command -v vercel >/dev/null 2>&1; then
    echo "ERROR: Vercel CLI is required to update MOMENTUM_DOWNLOAD_URL." >&2
    exit 1
  fi
  if printf '%s' "$DOWNLOAD_URL" | vercel env update MOMENTUM_DOWNLOAD_URL production --yes --cwd "$WEBSITE_DIR"; then
    :
  else
    printf '%s' "$DOWNLOAD_URL" | vercel env add MOMENTUM_DOWNLOAD_URL production --force --yes --cwd "$WEBSITE_DIR"
  fi
  if [[ "${MOMENTUM_DEPLOY_WEBSITE:-${CAMIFIT_DEPLOY_WEBSITE:-0}}" == "1" ]]; then
    vercel deploy --prod --yes --cwd "$WEBSITE_DIR"
  fi
fi

echo "$DOWNLOAD_URL"
