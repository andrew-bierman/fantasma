#!/usr/bin/env bash
# Builds Fantasma.app, installs it to ~/Applications, launches it, and
# links the `fantasma` CLI into ~/.local/bin.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/scripts/build-app.sh"

DEST="${HOME}/Applications"
mkdir -p "$DEST"
rm -rf "$DEST/Fantasma.app"
cp -R "$ROOT/Fantasma.app" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/Fantasma.app" 2>/dev/null || true

mkdir -p "${HOME}/.local/bin"
ln -sf "$DEST/Fantasma.app/Contents/MacOS/Fantasma" "${HOME}/.local/bin/fantasma"

open "$DEST/Fantasma.app"
echo "Installed and launched: $DEST/Fantasma.app"
echo "CLI linked: ~/.local/bin/fantasma (+new-window, +toggle-float, +show-config, +list-themes)"
