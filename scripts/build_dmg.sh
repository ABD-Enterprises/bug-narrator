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
ALLOW_NOTARIZATION_FAILURE="${ALLOW_NOTARIZATION_FAILURE:-NO}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-$ROOT_DIR/Resources/BugNarrator.entitlements}"
VOLUME_NAME="${VOLUME_NAME:-BugNarrator}"
APP_NAME="${APP_NAME:-BugNarrator}"
BACKGROUND_DIR_NAME=".background"
BACKGROUND_IMAGE_NAME="dmg-background.png"
BACKGROUND_RENDER_SCRIPT="${BACKGROUND_RENDER_SCRIPT:-$ROOT_DIR/scripts/render_dmg_background.swift}"
DMGBUILD_PYTHON_BIN="${DMGBUILD_PYTHON_BIN:-$ROOT_DIR/build/dmg-venv/bin/python}"
DMGBUILD_SETTINGS_PATH="${DMGBUILD_SETTINGS_PATH:-$ROOT_DIR/scripts/dmgbuild_settings.py}"
DMG_WINDOW_LEFT="${DMG_WINDOW_LEFT:-180}"
DMG_WINDOW_TOP="${DMG_WINDOW_TOP:-120}"
DMG_WINDOW_WIDTH="${DMG_WINDOW_WIDTH:-680}"
DMG_WINDOW_HEIGHT="${DMG_WINDOW_HEIGHT:-420}"
DMG_ICON_SIZE="${DMG_ICON_SIZE:-148}"
DMG_TEXT_SIZE="${DMG_TEXT_SIZE:-16}"
DMG_APP_ICON_X="${DMG_APP_ICON_X:-170}"
DMG_APP_ICON_Y="${DMG_APP_ICON_Y:-190}"
DMG_APPLICATIONS_ICON_X="${DMG_APPLICATIONS_ICON_X:-510}"
DMG_APPLICATIONS_ICON_Y="${DMG_APPLICATIONS_ICON_Y:-190}"
REQUIRE_RELEASE_SMOKE_TEST="${REQUIRE_RELEASE_SMOKE_TEST:-YES}"
RUN_STARTUP_KEYCHAIN_SMOKE="${RUN_STARTUP_KEYCHAIN_SMOKE:-YES}"
RELEASE_SMOKE_TEST_SCRIPT="${RELEASE_SMOKE_TEST_SCRIPT:-$ROOT_DIR/scripts/release_smoke_test.sh}"
MANUAL_DISTRIBUTION_SIGNING="NO"
VERIFY_MOUNTPOINT=""
VERIFY_DEVICE=""

detach_attachment() {
    local target="$1"
    local mountpoint="$2"
    local attempt

    if [[ -n "$target" || -n "$mountpoint" ]]; then
        if [[ -z "$target" ]]; then
            target="$mountpoint"
        fi

        if [[ -n "$mountpoint" && -d "$mountpoint" ]] && mount | grep -Fq "on $mountpoint "; then
            for attempt in 1 2 3; do
                if hdiutil detach "$target" -quiet >/dev/null 2>&1; then
                    break
                fi
                sleep 1
            done

            if mount | grep -Fq "on $mountpoint "; then
                hdiutil detach "$target" -force -quiet >/dev/null 2>&1 || true
                sleep 1
            fi
        fi
    fi

    if [[ -n "$mountpoint" && -d "$mountpoint" ]]; then
        rmdir "$mountpoint" 2>/dev/null || true
    fi
}

cleanup_mountpoints() {
    detach_attachment "$VERIFY_DEVICE" "$VERIFY_MOUNTPOINT"
}

verify_notarization_access() {
    local notarization_check_output
    local notarization_check_status

    set +e
    notarization_check_output="$(xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json 2>&1)"
    notarization_check_status=$?
    set -e

    if [[ "$notarization_check_status" -ne 0 ]]; then
        printf '%s\n' "$notarization_check_output" >&2
        echo "error: notarization preflight failed before building release artifacts." >&2

        if [[ "$notarization_check_output" == *"required agreement is missing or has expired"* ]]; then
            echo "error: Apple Developer Program agreements must be accepted before BugNarrator can be notarized for distribution." >&2
        fi

        echo "hint: resolve the Apple notarization account problem first, or rerun with NOTARIZE=NO for a non-distributable signed-only internal build." >&2
        exit 1
    fi
}

write_release_artifacts() {
    cp "$VERSIONED_DMG_PATH" "$STABLE_DMG_PATH"

    (
        cd "$OUTPUT_DIR"
        shasum -a 256 "$VERSIONED_DMG_NAME" >"$(basename "$VERSIONED_DMG_CHECKSUM_PATH")"
        shasum -a 256 "$STABLE_DMG_NAME" >"$(basename "$STABLE_DMG_CHECKSUM_PATH")"
    )
}

emit_release_summary() {
    echo "Built $APP_NAME $VERSION ($BUILD_NUMBER)"
    if [[ -n "$SIGNING_AUTHORITY" ]]; then
        echo "Signing authority: $SIGNING_AUTHORITY"
    fi
    echo "Release app: $APP_PATH"
    echo "Versioned DMG: $VERSIONED_DMG_PATH"
    if [[ -f "$STABLE_DMG_PATH" ]]; then
        echo "Stable DMG: $STABLE_DMG_PATH"
    fi
    if [[ -f "$VERSIONED_DMG_CHECKSUM_PATH" ]]; then
        echo "Versioned DMG checksum: $VERSIONED_DMG_CHECKSUM_PATH"
    fi
    if [[ -f "$STABLE_DMG_CHECKSUM_PATH" ]]; then
        echo "Stable DMG checksum: $STABLE_DMG_CHECKSUM_PATH"
    fi
}

has_boolean_entitlement() {
    local app_path="$1"
    local entitlement_key="$2"
    local entitlements_file

    entitlements_file="$(mktemp "${TMPDIR:-/tmp}/bugnarrator-entitlements.XXXXXX.plist")"

    if ! codesign -d --entitlements :- "$app_path" >"$entitlements_file" 2>/dev/null; then
        rm -f "$entitlements_file"
        return 1
    fi

    if /usr/bin/python3 - "$entitlements_file" "$entitlement_key" <<'PY'
import plistlib
import sys

entitlements_path = sys.argv[1]
entitlement_key = sys.argv[2]

with open(entitlements_path, "rb") as handle:
    entitlements = plistlib.load(handle)

sys.exit(0 if entitlements.get(entitlement_key) is True else 1)
PY
    then
        rm -f "$entitlements_file"
        return 0
    fi

    rm -f "$entitlements_file"
    return 1
}

trap cleanup_mountpoints EXIT

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

if [[ "$NOTARIZE" == "YES" && "$ALLOW_NOTARIZATION_FAILURE" != "YES" ]]; then
    echo "Running notarization preflight..."
    verify_notarization_access
fi

if [[ "$REQUIRE_RELEASE_SMOKE_TEST" == "YES" ]]; then
    if [[ ! -f "$RELEASE_SMOKE_TEST_SCRIPT" ]]; then
        echo "error: release smoke test script not found at $RELEASE_SMOKE_TEST_SCRIPT" >&2
        exit 1
    fi

    echo "Running release smoke preflight..."
    PROJECT_PATH="$PROJECT_PATH" \
    SCHEME="$SCHEME" \
    DERIVED_DATA_PATH="$DERIVED_DATA_PATH" \
    RUN_STARTUP_KEYCHAIN_SMOKE="$RUN_STARTUP_KEYCHAIN_SMOKE" \
    bash "$RELEASE_SMOKE_TEST_SCRIPT"
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

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: built app not found at $APP_PATH" >&2
    exit 1
fi

SIGNING_AUTHORITY=""
if [[ "$CODE_SIGNING_ALLOWED" == "YES" ]]; then
    if [[ "$MANUAL_DISTRIBUTION_SIGNING" == "YES" ]]; then
        codesign_args=(
            --force
            --deep
            --options runtime
            --timestamp
            --sign "$CODE_SIGN_IDENTITY"
        )

        if [[ -f "$ENTITLEMENTS_PATH" ]]; then
            codesign_args+=(
                --entitlements "$ENTITLEMENTS_PATH"
            )
        fi

        codesign "${codesign_args[@]}" "$APP_PATH"
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

    if ! has_boolean_entitlement "$APP_PATH" "com.apple.security.device.audio-input"; then
        echo "error: expected microphone entitlement com.apple.security.device.audio-input=true on the signed app at $APP_PATH" >&2
        exit 1
    fi
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
APP_ICON_ICNS_PATH="$APP_PATH/Contents/Resources/AppIcon.icns"
APP_ASSETS_CAR_PATH="$APP_PATH/Contents/Resources/Assets.car"
STAGING_BACKGROUND_DIR="$STAGING_DIR/$BACKGROUND_DIR_NAME"
STAGING_BACKGROUND_PATH="$STAGING_BACKGROUND_DIR/$BACKGROUND_IMAGE_NAME"

if [[ ! -f "$APP_ICON_ICNS_PATH" ]]; then
    echo "error: expected app icon resource at $APP_ICON_ICNS_PATH" >&2
    exit 1
fi

if [[ ! -f "$APP_ASSETS_CAR_PATH" ]]; then
    echo "error: expected asset catalog resource at $APP_ASSETS_CAR_PATH" >&2
    exit 1
fi

if [[ ! -x "$DMGBUILD_PYTHON_BIN" ]]; then
    echo "error: dmgbuild virtualenv python was not found at $DMGBUILD_PYTHON_BIN" >&2
    echo "Create the packaging virtualenv with:" >&2
    echo "  python3 -m venv build/dmg-venv" >&2
    echo "  build/dmg-venv/bin/python -m pip install dmgbuild" >&2
    exit 1
fi

if ! "$DMGBUILD_PYTHON_BIN" -c 'import dmgbuild' >/dev/null 2>&1; then
    echo "error: dmgbuild is not importable from $DMGBUILD_PYTHON_BIN" >&2
    echo "Refresh the packaging virtualenv with:" >&2
    echo "  build/dmg-venv/bin/python -m pip install --upgrade pip dmgbuild" >&2
    exit 1
fi

if [[ ! -f "$DMGBUILD_SETTINGS_PATH" ]]; then
    echo "error: dmgbuild settings file not found at $DMGBUILD_SETTINGS_PATH" >&2
    exit 1
fi

VERSIONED_DMG_NAME="${APP_NAME}-v${VERSION}-macOS.dmg"
STABLE_DMG_NAME="${APP_NAME}-macOS.dmg"
VERSIONED_DMG_PATH="$OUTPUT_DIR/$VERSIONED_DMG_NAME"
STABLE_DMG_PATH="$OUTPUT_DIR/$STABLE_DMG_NAME"
VERSIONED_DMG_CHECKSUM_PATH="$OUTPUT_DIR/${VERSIONED_DMG_NAME}.sha256"
STABLE_DMG_CHECKSUM_PATH="$OUTPUT_DIR/${STABLE_DMG_NAME}.sha256"

rm -f "$VERSIONED_DMG_PATH" "$STABLE_DMG_PATH" "$VERSIONED_DMG_CHECKSUM_PATH" "$STABLE_DMG_CHECKSUM_PATH"

mkdir -p "$STAGING_BACKGROUND_DIR"
swift "$BACKGROUND_RENDER_SCRIPT" "$STAGING_BACKGROUND_PATH"

"$DMGBUILD_PYTHON_BIN" -m dmgbuild \
    -s "$DMGBUILD_SETTINGS_PATH" \
    -D "app_path=$APP_PATH" \
    -D "background_path=$STAGING_BACKGROUND_PATH" \
    -D "volume_icon_path=$APP_ICON_ICNS_PATH" \
    -D "window_left=$DMG_WINDOW_LEFT" \
    -D "window_top=$DMG_WINDOW_TOP" \
    -D "window_width=$DMG_WINDOW_WIDTH" \
    -D "window_height=$DMG_WINDOW_HEIGHT" \
    -D "icon_size=$DMG_ICON_SIZE" \
    -D "text_size=$DMG_TEXT_SIZE" \
    -D "app_icon_x=$DMG_APP_ICON_X" \
    -D "app_icon_y=$DMG_APP_ICON_Y" \
    -D "applications_icon_x=$DMG_APPLICATIONS_ICON_X" \
    -D "applications_icon_y=$DMG_APPLICATIONS_ICON_Y" \
    "$VOLUME_NAME" \
    "$VERSIONED_DMG_PATH"

rm -rf "$STAGING_DIR"

VERIFY_MOUNTPOINT="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}-dmg-check.XXXXXX")"
VERIFY_MOUNTPOINT="$(cd "$VERIFY_MOUNTPOINT" && pwd -P)"
verify_attach_output="$(hdiutil attach "$VERSIONED_DMG_PATH" -readonly -nobrowse -mountpoint "$VERIFY_MOUNTPOINT")"
VERIFY_DEVICE="$(printf '%s\n' "$verify_attach_output" | awk -v mountpoint="$VERIFY_MOUNTPOINT" '$NF == mountpoint {print $1; exit}')"

if [[ -z "$VERIFY_DEVICE" ]]; then
    echo "error: could not determine the mounted device for DMG verification" >&2
    exit 1
fi

MOUNTED_APP_PATH="$VERIFY_MOUNTPOINT/$APP_NAME.app"
MOUNTED_APPLICATIONS_LINK="$VERIFY_MOUNTPOINT/Applications"

if [[ ! -d "$MOUNTED_APP_PATH" ]]; then
    echo "error: mounted DMG does not contain $APP_NAME.app" >&2
    exit 1
fi

if [[ ! -L "$MOUNTED_APPLICATIONS_LINK" ]]; then
    echo "error: mounted DMG does not contain an Applications shortcut" >&2
    exit 1
fi

if [[ ! -f "$MOUNTED_APP_PATH/Contents/Resources/AppIcon.icns" ]]; then
    echo "error: mounted DMG app is missing AppIcon.icns" >&2
    exit 1
fi

if [[ ! -f "$MOUNTED_APP_PATH/Contents/Resources/Assets.car" ]]; then
    echo "error: mounted DMG app is missing Assets.car" >&2
    exit 1
fi

if [[ "$CODE_SIGNING_ALLOWED" == "YES" ]] && ! has_boolean_entitlement "$MOUNTED_APP_PATH" "com.apple.security.device.audio-input"; then
    echo "error: expected microphone entitlement com.apple.security.device.audio-input=true on the mounted DMG app at $MOUNTED_APP_PATH" >&2
    exit 1
fi

if [[ ! -f "$VERIFY_MOUNTPOINT/.VolumeIcon.icns" ]]; then
    echo "error: mounted DMG is missing .VolumeIcon.icns" >&2
    exit 1
fi

if [[ ! -f "$VERIFY_MOUNTPOINT/.background.png" ]]; then
    echo "error: mounted DMG is missing the custom Finder background image" >&2
    exit 1
fi

if [[ "$(GetFileInfo -a "$VERIFY_MOUNTPOINT" 2>/dev/null || true)" != *"C"* ]]; then
    echo "warning: mounted DMG volume is missing the custom icon flag" >&2
fi

detach_attachment "$VERIFY_DEVICE" "$VERIFY_MOUNTPOINT"
VERIFY_MOUNTPOINT=""
VERIFY_DEVICE=""

if [[ "$NOTARIZE" == "YES" ]]; then
    echo "Submitting DMG for notarization with profile '$NOTARY_PROFILE'..."
    set +e
    notarize_output="$(xcrun notarytool submit "$VERSIONED_DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)"
    notarize_status=$?
    set -e

    if [[ "$notarize_status" -ne 0 ]]; then
        printf '%s\n' "$notarize_output" >&2
        echo "error: app signing succeeded, but notarization failed for $VERSIONED_DMG_PATH" >&2

        if [[ "$notarize_output" == *"required agreement is missing or has expired"* ]]; then
            echo "error: Apple Developer Program agreements must be accepted before notarization can continue." >&2
        fi

        if [[ "$ALLOW_NOTARIZATION_FAILURE" == "YES" ]]; then
            write_release_artifacts
            echo "warning: continuing because ALLOW_NOTARIZATION_FAILURE=YES. The generated DMG is signed but not notarized and must not be used as a public release artifact." >&2
            emit_release_summary
            exit 0
        fi

        echo "hint: resolve the notarization error and rerun, or use NOTARIZE=NO for a signed-only internal build." >&2
        echo "hint: if you need the script to preserve the signed DMG when notarization fails, rerun with ALLOW_NOTARIZATION_FAILURE=YES." >&2
        echo "Signed DMG path: $VERSIONED_DMG_PATH" >&2
        exit 1
    fi

    printf '%s\n' "$notarize_output"
    xcrun stapler staple -v "$VERSIONED_DMG_PATH"
    xcrun stapler validate "$VERSIONED_DMG_PATH"
    if ! dmg_spctl_output="$(spctl -a -vv -t open "$VERSIONED_DMG_PATH" 2>&1)"; then
        if [[ "$dmg_spctl_output" == *"Insufficient Context"* ]]; then
            echo "warning: spctl could not fully assess the local DMG (Insufficient Context). This is expected for some locally built, non-quarantined disk images. Rely on stapler validation here and do a second-Mac download smoke test before publishing." >&2
        else
            printf '%s\n' "$dmg_spctl_output" >&2
            exit 1
        fi
    else
        printf '%s\n' "$dmg_spctl_output"
    fi

    spctl -a -vv "$APP_PATH"
fi

write_release_artifacts
emit_release_summary
