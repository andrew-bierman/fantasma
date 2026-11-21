#!/usr/bin/env bash
# Validates release readiness: VERSION file, bundle plist agreement, clean
# tree on main, and that the v$VERSION tag does not already exist.
# Tags are immutable — if v$VERSION exists, bump VERSION instead.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() { echo "release-check FAILED: $*" >&2; exit 1; }

[ -f VERSION ] || fail "VERSION file missing"
VERSION="$(tr -d '[:space:]' < VERSION)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "VERSION '$VERSION' is not semver"

BRANCH="$(git branch --show-current)"
[ "$BRANCH" = "main" ] || fail "releases are cut from main (on: $BRANCH)"

[ -z "$(git status --porcelain)" ] || fail "working tree is dirty"

git fetch --tags -q
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  fail "tag v$VERSION already exists — tags are immutable, bump VERSION instead"
fi

PLIST_VERSION="$($ROOT/Fantasma.app/Contents/Info.plist \
  >/dev/null 2>&1 && /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$ROOT/Fantasma.app/Contents/Info.plist" 2>/dev/null || echo missing)"
if [ "$PLIST_VERSION" != "missing" ] && [ "$PLIST_VERSION" != "$VERSION" ]; then
  fail "bundle plist version ($PLIST_VERSION) != VERSION ($VERSION)"
fi

echo "release-check OK: v$VERSION from main @ $(git rev-parse --short HEAD)"
