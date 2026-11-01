#!/usr/bin/env bash
#
# Builds "AutoType Settings.app" — the menu bar companion — and installs it
# into /Applications.
#
# Usage: Scripts/package_app.sh [--install] [--debug]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/Scripts/env.sh"

CONFIGURATION="release"
INSTALL=0

for argument in "$@"; do
    case "$argument" in
        --install) INSTALL=1 ;;
        --debug) CONFIGURATION="debug" ;;
        *) echo "unknown option: $argument" >&2; exit 2 ;;
    esac
done

BUNDLE_ID="digital.autotype.AutoTypeSettings"
EXECUTABLE="AutoTypeSettings"
APP_NAME="AutoType Settings"
DIST="$ROOT/.build/dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"

echo "==> Building $EXECUTABLE ($CONFIGURATION)"
swift build --disable-sandbox \
    --cache-path "$AUTOTYPE_ROOT/.build/cache" \
    --configuration "$CONFIGURATION" \
    --product "$EXECUTABLE"

BIN_DIR="$(swift build --disable-sandbox \
    --cache-path "$AUTOTYPE_ROOT/.build/cache" \
    --configuration "$CONFIGURATION" \
    --product "$EXECUTABLE" \
    --show-bin-path)"

echo "==> Building icons"
python3 "$ROOT/Scripts/make_icon.py"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_DIR/$EXECUTABLE" "$CONTENTS/MacOS/$EXECUTABLE"

# The SwiftPM resource bundle carries the dictionaries.
for candidate in "$BIN_DIR"/*_AutoTypeCore.bundle; do
    [ -d "$candidate" ] || continue
    cp -R "$candidate" "$CONTENTS/Resources/"
done

cp "$ROOT/.build/icons/AutoType.icns" "$CONTENTS/Resources/AutoType.icns"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AutoType</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsSuddenTermination</key>
    <true/>
    <key>SMPrivilegedExecutables</key>
    <array/>
    <key>NSHumanReadableCopyright</key>
    <string>AutoType</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || {
    echo "warning: codesign failed; the bundle will still run locally" >&2
}

echo "==> Verifying"
codesign --verify --deep --strict "$APP" 2>&1 | head -3 || true

if [ "$INSTALL" -eq 1 ]; then
    if [ -w /Applications ]; then
        DESTINATION="/Applications/$APP_NAME.app"
    else
        DESTINATION="$HOME/Applications/$APP_NAME.app"
        mkdir -p "$HOME/Applications"
    fi
    echo "==> Installing to $DESTINATION"
    rm -rf "$DESTINATION"
    cp -R "$APP" "$DESTINATION"
    echo "==> Done."
else
    echo "==> Built $APP"
fi
