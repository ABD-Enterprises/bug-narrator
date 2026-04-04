#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/BugNarrator.xcodeproj}"
SCHEME="${SCHEME:-BugNarrator}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/DerivedData}"
CLEAN_LOCAL_BUILD_APPS="${CLEAN_LOCAL_BUILD_APPS:-NO}"
RUN_STARTUP_KEYCHAIN_SMOKE="${RUN_STARTUP_KEYCHAIN_SMOKE:-YES}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/BugNarrator.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"

if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "error: Xcode project not found at $PROJECT_PATH" >&2
    exit 1
fi

if [[ "$ROOT_DIR/project.yml" -nt "$PROJECT_PATH/project.pbxproj" ]]; then
    echo "Regenerating Xcode project with xcodegen..."
    (cd "$ROOT_DIR" && xcodegen generate)
fi

echo "Running debug tests..."
xcodebuild \
    -quiet \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    test

echo "Running unsigned release build..."
xcodebuild \
    -quiet \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    build

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: release app not found at $APP_PATH" >&2
    exit 1
fi

if [[ ! -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]]; then
    echo "error: release app is missing AppIcon.icns" >&2
    exit 1
fi

if [[ ! -f "$APP_PATH/Contents/Resources/Assets.car" ]]; then
    echo "error: release app is missing Assets.car" >&2
    exit 1
fi

MICROPHONE_USAGE_DESCRIPTION="$(/usr/libexec/PlistBuddy -c 'Print :NSMicrophoneUsageDescription' "$INFO_PLIST" 2>/dev/null || true)"
if [[ -z "$MICROPHONE_USAGE_DESCRIPTION" ]]; then
    echo "error: release app Info.plist is missing NSMicrophoneUsageDescription" >&2
    exit 1
fi

if [[ "$RUN_STARTUP_KEYCHAIN_SMOKE" == "YES" ]]; then
    echo "Running startup keychain smoke test..."
    APP_PATH="$APP_PATH" "$ROOT_DIR/scripts/keychain_startup_smoke_test.sh"
fi

echo "Release smoke test passed."
echo "Release app: $APP_PATH"

if [[ "$CLEAN_LOCAL_BUILD_APPS" == "YES" ]]; then
    echo "Cleaning local build app bundles..."
    "$ROOT_DIR/scripts/cleanup_local_build_apps.sh"
fi
