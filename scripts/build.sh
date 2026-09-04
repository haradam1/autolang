#!/usr/bin/env bash
# Build AutoLang.app.
#
# We compile with swiftc directly rather than `swift build` because the
# Command Line Tools' SwiftPM manifest library is currently broken on this
# machine (missing PackageDescription symbol). swiftc + a hand-assembled bundle
# is what SwiftPM would do under the hood anyway. If you install full Xcode,
# `swift build` / an Xcode project become options too.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/AutoLang.app"
MACOS="$APP/Contents/MacOS"
BIN="$MACOS/AutoLang"

echo "› compiling…"
rm -rf "$APP"
mkdir -p "$MACOS"

swiftc -swift-version 5 -O \
    -o "$BIN" \
    "$ROOT"/Sources/AutoLang/*.swift \
    -framework AppKit -framework Carbon -framework CoreGraphics -framework ServiceManagement

echo "› assembling bundle…"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Prefer the stable self-signed identity (scripts/setup-signing.sh) so the
# Accessibility grant survives rebuilds. Fall back to ad-hoc if it's absent.
IDENTITY_HASH="$(security find-identity -p codesigning 2>/dev/null \
    | grep 'AutoLang Self-Signed' | head -1 | awk '{print $2}')"

if [ -n "$IDENTITY_HASH" ]; then
    echo "› code signing with stable identity ($IDENTITY_HASH)…"
    codesign --force --sign "$IDENTITY_HASH" "$APP" >/dev/null 2>&1 \
        && echo "  ✓ signed — Accessibility grant will persist across rebuilds" \
        || echo "  ⚠ signing failed; falling back is manual (see scripts/setup-signing.sh)"
else
    echo "› no stable identity found — ad-hoc signing (run scripts/setup-signing.sh once to stop re-granting)…"
    codesign --force --sign - "$APP" >/dev/null 2>&1 || true
fi

echo "✓ built $APP"
echo
echo "First run:"
echo "  open \"$APP\""
echo "  → grant Accessibility when prompted (System Settings ▸ Privacy & Security ▸ Accessibility)"
echo "  → relaunch. Look for the ⌘ EN / ⌘ עב badge in the menu bar."
echo "  → type a word, press Control-Option-H to convert it."
