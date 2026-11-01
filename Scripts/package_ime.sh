#!/usr/bin/env bash
#
# Builds AutoType.app — the macOS input method bundle — and installs it into
# ~/Library/Input Methods so macOS can register it as an input source.
#
# Usage: Scripts/package_ime.sh [--install] [--debug]

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

BUNDLE_ID="digital.autotype.inputmethod.AutoType"
DIST="$ROOT/.build/dist"
APP="$DIST/AutoType.app"
CONTENTS="$APP/Contents"

echo "==> Building AutoType ($CONFIGURATION)"
swift build --disable-sandbox \
    --cache-path "$AUTOTYPE_ROOT/.build/cache" \
    --configuration "$CONFIGURATION" \
    --product AutoTypeIME

BIN_DIR="$(swift build --disable-sandbox \
    --cache-path "$AUTOTYPE_ROOT/.build/cache" \
    --configuration "$CONFIGURATION" \
    --product AutoTypeIME \
    --show-bin-path)"

echo "==> Building icons"
python3 "$ROOT/Scripts/make_icon.py"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_DIR/AutoTypeIME" "$CONTENTS/MacOS/AutoTypeIME"

# The SwiftPM resource bundle carries the dictionaries.
for candidate in "$BIN_DIR"/*_AutoTypeCore.bundle; do
    [ -d "$candidate" ] || continue
    cp -R "$candidate" "$CONTENTS/Resources/"
done

cp "$ROOT/.build/icons/AutoType.icns" "$CONTENTS/Resources/AutoType.icns"
cp "$ROOT/.build/icons/AutoTypeMenuTemplate.png" "$CONTENTS/Resources/"
cp "$ROOT/.build/icons/AutoTypeMenuTemplate@2x.png" "$CONTENTS/Resources/"

mkdir -p "$CONTENTS/Resources/en.lproj" "$CONTENTS/Resources/fa.lproj"
cat > "$CONTENTS/Resources/en.lproj/InfoPlist.strings" <<STRINGS
CFBundleName = "AutoType";
CFBundleDisplayName = "AutoType";
"$BUNDLE_ID" = "AutoType";
STRINGS
cat > "$CONTENTS/Resources/fa.lproj/InfoPlist.strings" <<STRINGS
CFBundleName = "AutoType";
CFBundleDisplayName = "AutoType";
"$BUNDLE_ID" = "AutoType";
STRINGS

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>AutoTypeIME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>AutoType</string>
    <key>CFBundleDisplayName</key>
    <string>AutoType</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2.0-beta</string>
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

    <key>InputMethodConnectionName</key>
    <string>digital_autotype_imk_connection</string>
    <key>InputMethodServerControllerClass</key>
    <string>Controller</string>
    <key>InputMethodServerDelegateClass</key>
    <string>Controller</string>
    <key>IMKControllerClass</key>
    <string>Controller</string>
    <key>IMKDelegateClass</key>
    <string>Controller</string>
    <key>tsInputMethodPrincipalClass</key>
    <string>Controller</string>
    <key>tsInputMethodIconFileKey</key>
    <string>AutoType.icns</string>
    <key>tsInputMethodCharacterRepertoireKey</key>
    <array>
        <string>Arab</string>
    </array>
    <key>TISInputSourceID</key>
    <string>$BUNDLE_ID</string>
    <key>TISIntendedLanguage</key>
    <string>fa</string>
    <key>TISIconIsTemplate</key>
    <false/>

    <key>ComponentInputModeDict</key>
    <dict>
        <key>tsInputModeListKey</key>
        <dict>
            <key>$BUNDLE_ID</key>
            <dict>
                <key>TISInputSourceID</key>
                <string>$BUNDLE_ID</string>
                <key>TISIntendedLanguage</key>
                <string>fa</string>
                <key>tsInputModeScriptKey</key>
                <string>smUnicodeScript</string>
                <key>tsInputModeDefaultStateKey</key>
                <true/>
                <key>tsInputModeIsVisibleKey</key>
                <true/>
                <key>tsInputModePrimaryInScriptKey</key>
                <true/>
                <key>tsInputModeMenuIconFileKey</key>
                <string>AutoType.icns</string>
                <key>tsInputModePaletteIconFileKey</key>
                <string>AutoType.icns</string>
            </dict>
        </dict>
        <key>tsVisibleInputModeOrderedArrayKey</key>
        <array>
            <string>$BUNDLE_ID</string>
        </array>
    </dict>

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
    DESTINATION="$HOME/Library/Input Methods/AutoType.app"
    echo "==> Installing to $DESTINATION"
    mkdir -p "$HOME/Library/Input Methods"
    rm -rf "$DESTINATION"
    cp -R "$APP" "$DESTINATION"
    echo "==> Done. Add AutoType in System Settings › Keyboard › Input Sources."
else
    echo "==> Built $APP"
fi
