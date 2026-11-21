#!/usr/bin/env bash
# Cuts a release: runs release-check, builds the bundle, zips it, tags
# v$VERSION, publishes the GitHub release, and updates the Homebrew tap.
# Tags are immutable — re-running after a cut requires a VERSION bump.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

"$ROOT/scripts/release-check.sh"

VERSION="$(tr -d '[:space:]' < VERSION)"
TAP_REPO="${FANTASMA_TAP:-andrew-bierman/homebrew-tap}"
GH_CMD="gh"; command -v ghx >/dev/null 2>&1 && GH_CMD="ghx"

swift test -q
"$ROOT/scripts/build-app.sh"

# Opt-in notarization: FANTASMA_NOTARIZE=1 scripts/release.sh
# Requires the Developer ID cert + one-time `xcrun notarytool store-credentials
# fantasma-notary ...` (see scripts/notarize.sh header).
if [ "${FANTASMA_NOTARIZE:-0}" = "1" ]; then
  "$ROOT/scripts/notarize.sh"
fi

rm -rf "/tmp/Fantasma-$VERSION"
mkdir -p "/tmp/Fantasma-$VERSION"
cp -R "$ROOT/Fantasma.app" "/tmp/Fantasma-$VERSION/"
( cd /tmp && zip -qry "Fantasma-$VERSION-arm64.zip" "Fantasma-$VERSION" )

git tag "v$VERSION" main
git push -q origin "v$VERSION"
"$GH_CMD" release create "v$VERSION" "/tmp/Fantasma-$VERSION-arm64.zip" \
  --title "Fantasma v$VERSION" \
  --notes "See commits since the previous release. Apple silicon build."

# Update the tap cask sha256 for the new asset.
SHA256="$(shasum -a 256 "/tmp/Fantasma-$VERSION-arm64.zip" | cut -d' ' -f1)"
TAP_DIR="/tmp/homebrew-tap"
if [ -d "$TAP_DIR" ]; then
  sed -i '' -E "s/sha256 \".*\"/sha256 \"$SHA256\"/; s/version \".*\"/version \"$VERSION\"/" \
    "$TAP_DIR/Casks/fantasma.rb"
  ( cd "$TAP_DIR" && git add -A && git commit -q -m "🔖 fantasma $VERSION" \
    && git push -q origin main )
  echo "tap updated: $TAP_REPO"
fi

echo "Released v$VERSION"
