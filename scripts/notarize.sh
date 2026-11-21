#!/usr/bin/env bash
# Notarize Fantasma for distribution (opt-in; requires an Apple Developer account).
#
# One-time setup (interactive):
#   xcrun notarytool store-credentials fantasma-notary \
#     --apple-id you@example.com --team-id YOURTEAMID
#
# Then, after scripts/build-app.sh:
#   scripts/notarize.sh                    # auto-detect Developer ID identity
#   IDENTITY="Developer ID Application: ..." scripts/notarize.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
APP="$ROOT/Fantasma.app"

[ -d "$APP" ] || { echo "Fantasma.app not found — run scripts/build-app.sh first" >&2; exit 1; }

IDENTITY="${IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')}"
[ -n "$IDENTITY" ] || {
  echo "No Developer ID Application identity found in the keychain." >&2
  echo "Install your cert, or set IDENTITY=\"Developer ID Application: ...\"" >&2
  exit 1
}
echo "Signing with: $IDENTITY"

# Deep-sign nested code first (the GhosttyKit resource bundle), then the app,
# with the hardened runtime notarytool requires.
find "$APP/Contents/Resources" -name "*.bundle" -type d 2>/dev/null | while read -r bundle; do
  codesign --force --sign "$IDENTITY" --timestamp "$bundle"
done
codesign --force --deep --options runtime --sign "$IDENTITY" --timestamp "$APP"
codesign --verify --strict --verbose=2 "$APP"

ZIP="$ROOT/Fantasma-notarize.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Submitting to Apple notary service (this can take a few minutes)..."
SUBMIT_OUT="$(xcrun notarytool submit "$ZIP" --keychain-profile fantasma-notary --wait 2>&1)"
echo "$SUBMIT_OUT" | tail -5
echo "$SUBMIT_OUT" | grep -q "status: Accepted" || {
  echo "Notarization did not complete — fetch the log:" >&2
  echo "  xcrun notarytool log <submission-id> --keychain-profile fantasma-notary" >&2
  exit 1
}

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
rm -f "$ZIP"
echo "Notarized + stapled: $APP"
