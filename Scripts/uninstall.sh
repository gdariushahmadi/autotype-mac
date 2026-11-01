#!/usr/bin/env bash
#
# Removes AutoType: the input method, the settings app and the shared
# configuration.
#
# Usage: Scripts/uninstall.sh [--keep-settings]

set -euo pipefail

KEEP_SETTINGS=0
for argument in "$@"; do
    case "$argument" in
        --keep-settings) KEEP_SETTINGS=1 ;;
        *) echo "unknown option: $argument" >&2; exit 2 ;;
    esac
done

echo "==> Removing the input method"
rm -rf "$HOME/Library/Input Methods/AutoType.app"

echo "==> Removing the settings app"
rm -rf "$HOME/Applications/AutoType Settings.app"
rm -rf "/Applications/AutoType Settings.app"

if [ "$KEEP_SETTINGS" -eq 0 ]; then
    echo "==> Removing the shared configuration"
    rm -rf "$HOME/Library/Application Support/AutoType"
else
    echo "==> Keeping the shared configuration"
fi

echo "==> Removing the input source entry"
PLIST="$(mktemp -t autotype).plist"
if defaults export com.apple.HIToolbox "$PLIST" 2>/dev/null; then
    python3 - "$PLIST" <<'PY' 2>/dev/null || true
import plistlib
import sys

path = sys.argv[1]
with open(path, "rb") as handle:
    plist = plistlib.load(handle)

sources = plist.get("AppleEnabledInputSources", [])
kept = [source for source in sources if source.get("Bundle ID") not in ("digital.autotype.AutoType", "digital.autotype.inputmethod.AutoType")]
if kept != sources:
    plist["AppleEnabledInputSources"] = kept
    with open(path, "wb") as handle:
        plistlib.dump(plist, handle)
PY
    defaults import com.apple.HIToolbox "$PLIST" 2>/dev/null || true
    killall cfprefsd 2>/dev/null || true
fi
rm -f "$PLIST"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -u "$HOME/Library/Input Methods/AutoType.app" 2>/dev/null || true
    "$LSREGISTER" -u "$HOME/Applications/AutoType Settings.app" 2>/dev/null || true
fi

echo
echo "AutoType has been removed."
echo "If AutoType still shows up in the input menu, log out and back in."
