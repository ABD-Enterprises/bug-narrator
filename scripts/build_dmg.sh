#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/BugNarrator.xcodeproj}"
SCHEME="${SCHEME:-BugNarrator}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/DerivedData}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
STAGING_DIR="${STAGING_DIR:-$ROOT_DIR/build/dmg-staging}"
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"
CODE_SIGN_STYLE="${CODE_SIGN_STYLE:-Automatic}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
OTHER_CODE_SIGN_FLAGS="${OTHER_CODE_SIGN_FLAGS:-}"
ALLOW_PROVISIONING_UPDATES="${ALLOW_PROVISIONING_UPDATES:-NO}"
NOTARIZE="${NOTARIZE:-NO}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
VOLUME_NAME="${VOLUME_NAME:-BugNarrator}"
MANUAL_DISTRIBUTION_SIGNING="NO"

if [[ "$CODE_SIGN_IDENTITY" == Developer\ ID\ Application* && "$CODE_SIGN_STYLE" == "Automatic" ]]; then
    # Developer ID builds are direct-distribution builds and should not use
    # the development-targeted automatic signing mode from the project.
    CODE_SIGN_STYLE="Manual"
fi

if [[ "$CODE_SIGNING_ALLOWED" == "YES" && "$CODE_SIGN_IDENTITY" == Developer\ ID\ Application* ]]; then
    # Xcode's normal app signing path injects development entitlements such as
    # get-task-allow into this project. For public distribution builds, produce
    # an unsigned Release app and then re-sign it explicitly for Developer ID.
    MANUAL_DISTRIBUTION_SIGNING="YES"
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "error: Xcode project not found at $PROJECT_PATH" >&2
    exit 1
fi

if [[ "$NOTARIZE" == "YES" && "$CODE_SIGNING_ALLOWED" != "YES" ]]; then
    echo "error: notarization requires CODE_SIGNING_ALLOWED=YES" >&2
    exit 1
fi

if [[ "$NOTARIZE" == "YES" && -z "$NOTARY_PROFILE" ]]; then
    echo "error: notarization requires NOTARY_PROFILE to be set" >&2
    exit 1
fi

rm -rf "$STAGING_DIR"
mkdir -p "$OUTPUT_DIR" "$STAGING_DIR"

xcodebuild_args=(
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -derivedDataPath "$DERIVED_DATA_PATH"
    CODE_SIGNING_ALLOWED="$([[ "$MANUAL_DISTRIBUTION_SIGNING" == "YES" ]] && echo NO || echo "$CODE_SIGNING_ALLOWED")"
    CODE_SIGN_STYLE="$CODE_SIGN_STYLE"
)

if [[ "$CODE_SIGN_STYLE" == "Manual" ]]; then
    xcodebuild_args+=(
        PROVISIONING_PROFILE_SPECIFIER=
        PROVISIONING_PROFILE=
    )
fi

if [[ -n "$DEVELOPMENT_TEAM" ]]; then
    xcodebuild_args+=(
        DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
    )
fi

if [[ -n "$CODE_SIGN_IDENTITY" && "$MANUAL_DISTRIBUTION_SIGNING" != "YES" ]]; then
    xcodebuild_args+=(
        CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY"
    )
fi

if [[ -n "$OTHER_CODE_SIGN_FLAGS" ]]; then
    xcodebuild_args+=(
        OTHER_CODE_SIGN_FLAGS="$OTHER_CODE_SIGN_FLAGS"
    )
fi

if [[ "$ALLOW_PROVISIONING_UPDATES" == "YES" ]]; then
    xcodebuild_args+=(
        -allowProvisioningUpdates
    )
fi

xcodebuild "${xcodebuild_args[@]}" build

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/BugNarrator.app"

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: built app not found at $APP_PATH" >&2
    exit 1
fi

SIGNING_AUTHORITY=""
if [[ "$CODE_SIGNING_ALLOWED" == "YES" ]]; then
    if [[ "$MANUAL_DISTRIBUTION_SIGNING" == "YES" ]]; then
        codesign --force --deep --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$APP_PATH"
    fi

    CODESIGN_DETAILS="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
    SIGNING_AUTHORITY="$(printf '%s\n' "$CODESIGN_DETAILS" | awk -F= '/^Authority=/{print $2; exit}')"

    if [[ -z "$SIGNING_AUTHORITY" ]]; then
        echo "error: expected a signed app build, but could not determine the signing authority" >&2
        exit 1
    fi

    if [[ "$NOTARIZE" == "YES" && "$SIGNING_AUTHORITY" != Developer\ ID\ Application:* ]]; then
        echo "error: notarization requires a Developer ID Application signature, but the app is signed as: $SIGNING_AUTHORITY" >&2
        exit 1
    fi

    if [[ "$NOTARIZE" != "YES" && "$SIGNING_AUTHORITY" != Developer\ ID\ Application:* ]]; then
        echo "warning: app is signed as '$SIGNING_AUTHORITY'. Gatekeeper will still reject broad public distribution without Developer ID Application signing and notarization." >&2
    fi
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"

VERSIONED_DMG_NAME="BugNarrator-v${VERSION}-macOS.dmg"
STABLE_DMG_NAME="BugNarrator-macOS.dmg"
TEMP_DMG_PATH="$OUTPUT_DIR/BugNarrator-temp.dmg"
VERSIONED_DMG_PATH="$OUTPUT_DIR/$VERSIONED_DMG_NAME"
STABLE_DMG_PATH="$OUTPUT_DIR/$STABLE_DMG_NAME"

rm -f "$TEMP_DMG_PATH" "$VERSIONED_DMG_PATH" "$STABLE_DMG_PATH"

ditto "$APP_PATH" "$STAGING_DIR/BugNarrator.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -format UDRW \
    -ov \
    "$TEMP_DMG_PATH"

hdiutil convert \
    "$TEMP_DMG_PATH" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$VERSIONED_DMG_PATH"

rm -f "$TEMP_DMG_PATH"
rm -rf "$STAGING_DIR"

if [[ "$NOTARIZE" == "YES" ]]; then
    echo "Submitting DMG for notarization with profile '$NOTARY_PROFILE'..."
    xcrun notarytool submit "$VERSIONED_DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple -v "$VERSIONED_DMG_PATH"
    xcrun stapler validate "$VERSIONED_DMG_PATH"
    spctl -a -vv "$APP_PATH"
fi

cp "$VERSIONED_DMG_PATH" "$STABLE_DMG_PATH"

echo "Built BugNarrator $VERSION ($BUILD_NUMBER)"
if [[ -n "$SIGNING_AUTHORITY" ]]; then
    echo "Signing authority: $SIGNING_AUTHORITY"
fi
echo "Versioned DMG: $VERSIONED_DMG_PATH"
echo "Stable DMG: $STABLE_DMG_PATH"
