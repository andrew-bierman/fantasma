#!/usr/bin/env bash
# Builds Fantasma.app and installs it to ~/Applications, then launches it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/scripts/build-app.sh"

DEST="${HOME}/Applications"
mkdir -p "$DEST"
rm -rf "$DEST/Fantasma.app"
cp -R "$ROOT/Fantasma.app" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/Fantasma.app" 2>/dev/null || true

open "$DEST/Fantasma.app"
echo "Installed and launched: $DEST/Fantasma.app"
