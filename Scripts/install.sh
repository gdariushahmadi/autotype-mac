#!/usr/bin/env bash
#
# Builds and installs AutoType — the input method and the settings app.
#
# After this finishes, log out and log back in once so macOS notices the new
# input method, then add AutoType in
# System Settings › Keyboard › Text Input › Edit.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> Building the input method"
bash Scripts/package_ime.sh

echo
echo "==> Building the settings app"
bash Scripts/package_app.sh

echo
echo "==> Installing"

IME_SOURCE="$ROOT/.build/dist/AutoType.app"
IME_TARGET="$HOME/Library/Input Methods/AutoType.app"
APP_SOURCE="$ROOT/.build/dist/AutoType Settings.app"
APP_TARGET="$HOME/Applications/AutoType Settings.app"

mkdir -p "$HOME/Library/Input Methods" "$HOME/Applications"
rm -rf "$IME_TARGET" "$APP_TARGET"
cp -R "$IME_SOURCE" "$IME_TARGET"
cp -R "$APP_SOURCE" "$APP_TARGET"

# Tell LaunchServices about the new bundle so the icon shows up right away.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -f "$IME_TARGET" "$APP_TARGET" || true
fi

echo
echo "==> Registering and enabling the input source"

swift -e '
import Carbon
import Foundation

let path = NSString(string: "~/Library/Input Methods/AutoType.app").expandingTildeInPath
let url = URL(fileURLWithPath: path)
_ = TISRegisterInputSource(url as CFURL)

if let list = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] {
    for src in list {
        if let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) {
            let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
            if id.contains("autotype") {
                TISEnableInputSource(src)
            }
        }
    }
}
' || true

BUNDLE_ID="digital.autotype.inputmethod.AutoType"

PLIST="$(mktemp -t autotype).plist"
if defaults export com.apple.HIToolbox "$PLIST" 2>/dev/null; then
    python3 - "$PLIST" "$BUNDLE_ID" <<'PY' 2>/dev/null || true
import plistlib
import sys

path = sys.argv[1]
bundle_id = sys.argv[2]
with open(path, "rb") as handle:
    plist = plistlib.load(handle)

sources = plist.get("AppleEnabledInputSources", [])
# Remove old legacy entries if present
sources = [s for s in sources if s.get("Bundle ID") != "digital.autotype.AutoType"]

entries = [
    {"Bundle ID": bundle_id, "InputSourceKind": "Keyboard Input Method"},
    {"Bundle ID": bundle_id, "Input Mode": bundle_id, "InputSourceKind": "Input Mode"}
]

changed = False
for entry in entries:
    if not any(s.get("Bundle ID") == entry.get("Bundle ID") and s.get("InputSourceKind") == entry.get("InputSourceKind") for s in sources):
        sources.append(entry)
        changed = True

if changed or len(sources) != len(plist.get("AppleEnabledInputSources", [])):
    plist["AppleEnabledInputSources"] = sources
    with open(path, "wb") as handle:
        plistlib.dump(plist, handle)
PY
    defaults import com.apple.HIToolbox "$PLIST" 2>/dev/null || true
    killall cfprefsd 2>/dev/null || true
fi
rm -f "$PLIST"

echo
echo "==> Checking the input method"
"$IME_TARGET/Contents/MacOS/AutoTypeIME" --self-test

cat <<'MESSAGE'

AutoType is installed.

  Input method:  ~/Library/Input Methods/AutoType.app
  Settings app:  ~/Applications/AutoType Settings.app

Two steps are left:

  1. Log out and log back in (or restart the Mac). macOS only scans for new
     input methods when the user session starts.

  2. Open System Settings › Keyboard › Text Input › Edit…, press + and add
     AutoType.

The settings app in the menu bar tells you when step 2 is done.
MESSAGE
