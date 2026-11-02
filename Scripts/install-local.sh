#!/bin/bash
# Build Ice locally and install it into /Applications.
#
# Signing identity is pinned so the TCC grants (Accessibility, Screen
# Recording) survive rebuilds: permissions are keyed to the app's
# designated requirement, which for an "Apple Development" certificate
# references the certificate subject rather than the binary hash.
#
# Override the identity/team with env vars if the certificate is renewed:
#   SIGN_IDENTITY="Apple Development: name (XXXXXXXXXX)" SIGN_TEAM=XXXXXXXXXX ./Scripts/install-local.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGN_IDENTITY="${SIGN_IDENTITY:-Apple Development: zlh153200@icloud.com (NL6JWT93LX)}"
SIGN_TEAM="${SIGN_TEAM:-2W8MYZ8HF8}"
APP_NAME="Ice.app"
INSTALL_DIR="/Applications"
BUILD_DIR="$ROOT/.build"

if ! security find-identity -v -p codesigning | grep -qF "$SIGN_IDENTITY"; then
    echo "error: signing identity not found in keychain: $SIGN_IDENTITY" >&2
    echo "available identities:" >&2
    security find-identity -v -p codesigning | sed 's/^/  /' >&2
    exit 1
fi

echo "==> Building ($APP_NAME, Release)"
xcodebuild \
    -project "$ROOT/Ice.xcodeproj" \
    -scheme Ice \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    DEVELOPMENT_TEAM="$SIGN_TEAM" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    build

BUILT_APP="$BUILD_DIR/Build/Products/Release/$APP_NAME"
[ -d "$BUILT_APP" ] || { echo "error: build product missing at $BUILT_APP" >&2; exit 1; }

TARGET_APP="$INSTALL_DIR/$APP_NAME"
if [ -d "$TARGET_APP" ]; then
    existing_team="$(codesign -dv --verbose=2 "$TARGET_APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
    if [ "$existing_team" != "$SIGN_TEAM" ]; then
        echo "error: $TARGET_APP is signed by team '$existing_team', refusing to replace it" >&2
        exit 1
    fi
    if pgrep -x Ice >/dev/null; then
        echo "==> Quitting running Ice"
        osascript -e 'tell application "Ice" to quit' >/dev/null 2>&1 || pkill -x Ice || true
        sleep 1
    fi
    echo "==> Replacing $TARGET_APP"
    rm -rf "$TARGET_APP"
fi

echo "==> Installing to $TARGET_APP"
ditto "$BUILT_APP" "$TARGET_APP"

# Keep the fork from being replaced by an upstream Sparkle release; an
# upstream build may not run on this macOS version and would also reset
# the permission grants. Manual "Check for Updates" stays available.
defaults write com.jordanbaird.Ice SUEnableAutomaticChecks -bool false
defaults write com.jordanbaird.Ice SUAutomaticallyUpdate -bool false

echo "==> Verifying signature"
codesign --verify --deep --strict "$TARGET_APP"
codesign -dv --verbose=2 "$TARGET_APP" 2>&1 | egrep 'Identifier|Authority|TeamIdentifier'
codesign -d -r- "$TARGET_APP" 2>&1 | tail -1

echo
echo "Installed: $TARGET_APP"
echo "First launch will ask for Accessibility and Screen Recording; grants persist across rebuilds."
