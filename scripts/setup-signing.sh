#!/usr/bin/env bash
# One-time: create a stable self-signed code-signing identity for AutoLang.
#
# Why: ad-hoc signing (`-s -`) gives the app a new code identity on every build,
# which invalidates the macOS Accessibility (TCC) grant each time. Signing with a
# STABLE certificate keeps the app's "designated requirement" constant across
# rebuilds, so you grant Accessibility once and it sticks.
#
# Uses a dedicated keychain with its own password (below), so it never needs your
# login keychain password. The cert is self-signed and untrusted — that's fine:
# codesign signs with it by hash, and TCC keys on the cert's leaf hash, not trust.
#
# Fully reversible: scripts/remove-signing.sh.
#
# NOTE: re-running mints a NEW certificate (new leaf hash), which changes the
# designated requirement — you'd have to re-grant Accessibility once more. Run it
# only once unless you intend to reset.
set -euo pipefail

KC_NAME="autolang-signing"
KC_PASS="autolang-local"          # password for THIS keychain only (not your login)
P12_PASS="autolang"               # transient PKCS#12 transport password
CERT_CN="AutoLang Self-Signed"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "› generating self-signed code-signing certificate…"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$CERT_CN" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

# LibreSSL (system openssl) writes Apple-importable PKCS#12; a non-empty
# transport password is required or the MAC check fails on import.
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/cert.p12" -passout "pass:$P12_PASS" -name "$CERT_CN" >/dev/null 2>&1

echo "› (re)creating dedicated keychain '$KC_NAME'…"
security delete-keychain "$KC_NAME.keychain" 2>/dev/null || true
security create-keychain -p "$KC_PASS" "$KC_NAME.keychain"
security set-keychain-settings "$KC_NAME.keychain"          # no auto-lock timeout
security unlock-keychain -p "$KC_PASS" "$KC_NAME.keychain"

echo "› importing certificate + key…"
security import "$WORK/cert.p12" -k "$KC_NAME.keychain" -P "$P12_PASS" \
    -T /usr/bin/codesign -A >/dev/null 2>&1

echo "› authorizing codesign to use the key without prompting…"
security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "$KC_PASS" "$KC_NAME.keychain" >/dev/null 2>&1

echo "› adding keychain to the user search list…"
EXISTING=$(security list-keychains -d user | sed -e 's/[[:space:]]*"//' -e 's/"$//')
# shellcheck disable=SC2086
security list-keychains -d user -s "$KC_NAME.keychain" $EXISTING

HASH=$(security find-identity -p codesigning "$KC_NAME.keychain" \
    | grep "$CERT_CN" | head -1 | awk '{print $2}')
echo
echo "✓ done. Stable code-signing identity ready:"
echo "    $HASH  \"$CERT_CN\""
echo
echo "Now rebuild (scripts/build.sh will use it automatically), then grant"
echo "Accessibility ONE more time. After that, rebuilds keep the grant."
