#!/usr/bin/env bash
# fantasma installer: fetches the latest release and installs it.
# Usage: curl -fsSL https://raw.githubusercontent.com/andrew-bierman/fantasma/main/install.sh | sh
set -euo pipefail

REPO="andrew-bierman/fantasma"
DEST="${HOME}/Applications"

fail() { echo "fantasma install failed: $*" >&2; exit 1; }
[ "$(uname)" = "Darwin" ] || fail "macOS only"
[ "$(uname -m)" = "arm64" ] || fail "Apple silicon (arm64) only"

command -v python3 >/dev/null || fail "python3 required to resolve the latest release"
ASSET_URL="$(python3 - <<'PYEOF'
import json, urllib.request
req = urllib.request.Request(
    "https://api.github.com/repos/andrew-bierman/fantasma/releases/latest",
    headers={"Accept": "application/vnd.github+json"},
)
with urllib.request.urlopen(req) as r:
    data = json.load(r)
print(data["assets"][0]["browser_download_url"])
PYEOF
)"
[ -n "$ASSET_URL" ] || fail "could not resolve the latest release asset"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "Downloading $ASSET_URL"
curl -fsSL "$ASSET_URL" -o "$TMP/fantasma.zip" || fail "download failed"

mkdir -p "$DEST"
rm -rf "$DEST/Fantasma.app"
unzip -q "$TMP/fantasma.zip" -d "$TMP"
cp -R "$TMP/Fantasma-0.2.0/Fantasma.app" "$DEST/" 2>/dev/null ||
  cp -R "$TMP"/*.app "$DEST/" ||
  fail "could not find Fantasma.app in the archive"
rm -rf "$DEST/Fantasma.app/Contents/Resources/GhosttyKit_GhosttyTerminal.bundle/_CodeSignature" 2>/dev/null || true
xattr -dr com.apple.quarantine "$DEST/Fantasma.app" 2>/dev/null || true

mkdir -p "${HOME}/.local/bin"
ln -sf "$DEST/Fantasma.app/Contents/MacOS/Fantasma" "${HOME}/.local/bin/fantasma"

open "$DEST/Fantasma.app"
echo "Installed: $DEST/Fantasma.app"
echo "CLI:       ~/.local/bin/fantasma (+toggle-float, +new-window, +show-config, +list-themes)"
echo "Config:    ~/.config/fantasma/fantasma.conf"
