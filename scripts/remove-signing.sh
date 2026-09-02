#!/usr/bin/env bash
# Reverse scripts/setup-signing.sh: delete the dedicated signing keychain and
# drop it from the search list. Builds fall back to ad-hoc signing afterward.
set -euo pipefail
KC_NAME="autolang-signing"

security delete-keychain "$KC_NAME.keychain" 2>/dev/null \
    && echo "✓ removed $KC_NAME.keychain" \
    || echo "· $KC_NAME.keychain not present"

# Rebuild the user search list without our keychain.
REMAINING=$(security list-keychains -d user \
    | sed -e 's/[[:space:]]*"//' -e 's/"$//' \
    | grep -v "$KC_NAME" || true)
# shellcheck disable=SC2086
security list-keychains -d user -s $REMAINING
echo "✓ search list restored"
