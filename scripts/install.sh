#!/usr/bin/env bash
# Build and install AutoLang into /Applications, then relaunch from there.
#
# Why install: "Launch at login" registers the *running* bundle's path, and you
# generally want the app in /Applications rather than a dev folder. Because the
# app is signed with a stable identity, its designated requirement (and thus the
# Accessibility grant) is path-independent — moving it keeps the grant.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="/Applications/AutoLang.app"

bash "$ROOT/scripts/build.sh"

echo "› installing to $DEST"
pkill -x AutoLang 2>/dev/null || true
sleep 1
rm -rf "$DEST"
cp -R "$ROOT/AutoLang.app" "$DEST"

echo "› launching from /Applications"
open "$DEST"
echo "✓ installed and running from $DEST"
echo "  (If it shows the ⚠ icon, re-grant Accessibility once for the new copy.)"
