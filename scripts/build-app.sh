#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Fantasma"
APP="$ROOT/$APP_NAME.app"
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null | tr -d '[:space:]')"
VERSION="${VERSION:-0.0.0}"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/Fantasma" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"

# SPM resource bundles (Ghostty's shell integration + terminfo) must ship
# inside the app or ghostty_init crashes at launch.
find "$ROOT/.build" -maxdepth 4 -name "*.bundle" -type d 2>/dev/null | while read -r bundle; do
    # -f: SPM marks cached bundle files read-only (444); a pre-existing
    # destination (cached CI workspace) would fail a plain overwrite.
    cp -Rf "$bundle" "$APP/Contents/Resources/"
done

# Compile the layered icon and its fallback for older macOS versions.
ICON_PLIST="$ROOT/.build/app-icon.plist"
xcrun actool "$ROOT/Assets/AppIcon.icon" \
    --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 \
    --app-icon AppIcon --output-partial-info-plist "$ICON_PLIST"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Fantasma</string>
    <key>CFBundleIdentifier</key>
    <string>com.andrewbierman.fantasma</string>
    <key>CFBundleName</key>
    <string>Fantasma</string>
    <key>CFBundleDisplayName</key>
    <string>Fantasma</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppSleepDisabled</key>
    <true/>
</dict>
</plist>
PLIST
/usr/libexec/PlistBuddy -c "Merge '$ICON_PLIST'" "$APP/Contents/Info.plist"

# Ad-hoc signature so the app launches locally; a real Developer ID signature
# (needed for notarization) is applied by scripts/notarize.sh.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Built $APP"
