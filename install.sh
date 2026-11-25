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
for asset in data["assets"]:
    if asset["name"].endswith(".zip"):
        print(asset["browser_download_url"])
        break
PYEOF
)"
[ -n "$ASSET_URL" ] || fail "could not resolve the latest release asset"

TMP="$(mktemp -d)"
STAGE=""
CLI_STAGE=""
APP="$DEST/Fantasma.app"
CLI="${HOME}/.local/bin/fantasma"
APP_PUBLISHED=0
COMMITTED=0

cleanup() {
  if [ "$COMMITTED" -eq 0 ] && [ -n "$STAGE" ]; then
    if [ "$APP_PUBLISHED" -eq 1 ]; then
      mv "$APP" "$STAGE/failed.app" || {
        echo "fantasma rollback failed: staging retained at $STAGE" >&2
        STAGE=""
      }
    fi
    if [ -n "$STAGE" ] && { [ -e "$STAGE/previous.app" ] || [ -L "$STAGE/previous.app" ]; }; then
      mv "$STAGE/previous.app" "$APP" || {
        echo "fantasma rollback failed: previous app retained at $STAGE/previous.app" >&2
        STAGE=""
      }
    fi
  fi
  if [ -n "$STAGE" ]; then rm -rf "$STAGE"; fi
  if [ -n "$CLI_STAGE" ]; then rm -rf "$CLI_STAGE"; fi
  rm -rf "$TMP"
}
trap cleanup EXIT
echo "Downloading $ASSET_URL"
curl -fsSL "$ASSET_URL" -o "$TMP/fantasma.zip" || fail "download failed"
unzip -q "$TMP/fantasma.zip" -d "$TMP"

# Find the app in the archive.
APP_SRC=""
for candidate in "$TMP"/Fantasma-*/Fantasma.app "$TMP"/*.app; do
  if [ -d "$candidate" ]; then APP_SRC="$candidate"; break; fi
done
[ -n "$APP_SRC" ] || fail "could not find Fantasma.app in the archive"

mkdir -p "$DEST" "${CLI%/*}" || fail "could not create install directories"
# Keep staging and backups on the same filesystems as their final paths.
STAGE="$(mktemp -d "$DEST/.fantasma-install.XXXXXXXX")" || fail "could not create app staging directory"
cp -pRP "$APP_SRC" "$STAGE/Fantasma.app" || fail "could not stage Fantasma.app"
CLI_STAGE="$(mktemp -d "${CLI%/*}/.fantasma-install.XXXXXXXX")" || fail "could not create CLI staging directory"
ln -s "$APP/Contents/MacOS/Fantasma" "$CLI_STAGE/fantasma" || fail "could not stage CLI link"

if [ -e "$APP" ] || [ -L "$APP" ]; then
  mv "$APP" "$STAGE/previous.app" || fail "could not back up Fantasma.app"
fi
mv "$STAGE/Fantasma.app" "$APP" || fail "could not replace Fantasma.app"
APP_PUBLISHED=1
# Replace the CLI path itself, even when it is a symlink to a directory.
python3 -c 'import os, sys; os.replace(sys.argv[1], sys.argv[2])' \
  "$CLI_STAGE/fantasma" "$CLI" || fail "could not replace CLI link"
COMMITTED=1

open "$APP"
echo "Installed: $DEST/Fantasma.app"
echo "CLI:       ~/.local/bin/fantasma (+toggle-float, +new-window, +show-config, +list-themes)"
echo "Config:    ~/.config/fantasma/fantasma.conf"
