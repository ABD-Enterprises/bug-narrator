#!/usr/bin/env bash
set -euo pipefail

# Build a standalone macOS binary of the BugNarrator transcription server.
#
# Output: dist/bugnarrator-transcription (single executable, no Python required)
#
# Prerequisites: Python 3.12, Xcode command-line tools, and ffmpeg.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON="${PYTHON:-}"
BUILD_VENV_DIR="${BUILD_VENV_DIR:-$SCRIPT_DIR/build/standalone-venv}"
REQUIREMENTS_LOCK="$SCRIPT_DIR/requirements-standalone.lock"
ENTITLEMENTS_PATH="$SCRIPT_DIR/Standalone.entitlements"
DIST_DIR="$SCRIPT_DIR/dist"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
APP_NAME="bugnarrator-transcription"
RUN_TRANSCRIPTION_SMOKE_TEST="${RUN_TRANSCRIPTION_SMOKE_TEST:-YES}"
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
PUBLIC_RELEASE="${PUBLIC_RELEASE:-NO}"
NOTARIZE="${NOTARIZE:-NO}"
NOTARY_PROFILE="${NOTARY_PROFILE:-BugNarratorNotary}"
VERSION="$(tr -d '[:space:]' <"$ROOT_DIR/VERSION")"
ARCH="$(uname -m)"
RELEASE_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
RELEASE_TAG="$(git -C "$ROOT_DIR" describe --exact-match --tags HEAD 2>/dev/null || true)"
RELEASE_TREE_STATE="clean"

if [[ -n "$(git -C "$ROOT_DIR" status --porcelain 2>/dev/null)" ]]; then
    RELEASE_TREE_STATE="dirty"
fi

if [[ "$ARCH" != "arm64" ]]; then
    echo "error: the Parakeet standalone release currently supports Apple Silicon only; found $ARCH." >&2
    exit 1
fi

if [[ "$PUBLIC_RELEASE" == "YES" ]]; then
    if [[ "$RELEASE_TREE_STATE" != "clean" ]]; then
        echo "error: PUBLIC_RELEASE=YES requires a clean working tree." >&2
        git -C "$ROOT_DIR" status --porcelain >&2
        exit 1
    fi
    if [[ "$RELEASE_COMMIT" == "unknown" || "$RELEASE_TAG" != "v$VERSION" ]]; then
        echo "error: PUBLIC_RELEASE=YES requires HEAD to be exactly on tag v$VERSION." >&2
        exit 1
    fi
    if [[ "$CODE_SIGNING_ALLOWED" != "YES" || -z "$CODE_SIGN_IDENTITY" ]]; then
        echo "error: PUBLIC_RELEASE=YES requires a Developer ID CODE_SIGN_IDENTITY." >&2
        exit 1
    fi
    if [[ "$NOTARIZE" != "YES" ]]; then
        echo "error: PUBLIC_RELEASE=YES requires NOTARIZE=YES." >&2
        exit 1
    fi
    if [[ "$RUN_TRANSCRIPTION_SMOKE_TEST" != "YES" ]]; then
        echo "error: PUBLIC_RELEASE=YES cannot skip the packaged transcription smoke test." >&2
        exit 1
    fi
fi

if [[ "$NOTARIZE" == "YES" ]]; then
    if [[ "$CODE_SIGNING_ALLOWED" != "YES" || -z "$CODE_SIGN_IDENTITY" ]]; then
        echo "error: notarization requires a signed standalone binary." >&2
        exit 1
    fi
    echo "Checking Apple notarization access..."
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" \
        --output-format json >/dev/null
fi

if [[ -z "$PYTHON" ]]; then
    for candidate in python3.12; do
        if command -v "$candidate" >/dev/null 2>&1; then
            PYTHON="$(command -v "$candidate")"
            break
        fi
    done
fi

if [[ -z "$PYTHON" ]]; then
    echo "error: Python 3.12 is required to build the standalone server." >&2
    exit 1
fi

PYTHON_VERSION="$("$PYTHON" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
if [[ "$PYTHON_VERSION" != "3.12" ]]; then
    echo "error: standalone builds require Python 3.12; found $PYTHON_VERSION at $PYTHON." >&2
    exit 1
fi

echo "Creating clean standalone build environment with Python $PYTHON_VERSION..."
"$PYTHON" -m venv --clear "$BUILD_VENV_DIR"
"$BUILD_VENV_DIR/bin/python" -m pip install \
    --require-hashes \
    --only-binary=:all: \
    --requirement "$REQUIREMENTS_LOCK" \
    --quiet
PYINSTALLER_VERSION="$(
    "$BUILD_VENV_DIR/bin/python" -c \
        'from importlib.metadata import version; print(version("pyinstaller"))'
)"
PYINSTALLER_SIGNING_ARGS=()
if [[ "$CODE_SIGNING_ALLOWED" == "YES" ]]; then
    PYINSTALLER_SIGNING_ARGS=(
        --codesign-identity "$CODE_SIGN_IDENTITY"
        --osx-entitlements-file "$ENTITLEMENTS_PATH"
    )
fi

echo "Building standalone binary..."
"$BUILD_VENV_DIR/bin/python" -m PyInstaller \
    --name "$APP_NAME" \
    --onefile \
    --noconfirm \
    --clean \
    --distpath "$DIST_DIR" \
    --workpath "$SCRIPT_DIR/build/pyinstaller" \
    --specpath "$SCRIPT_DIR/build/pyinstaller" \
    --collect-all parakeet_mlx \
    --collect-all mlx \
    --hidden-import uvicorn.logging \
    --hidden-import uvicorn.loops \
    --hidden-import uvicorn.loops.auto \
    --hidden-import uvicorn.protocols \
    --hidden-import uvicorn.protocols.http \
    --hidden-import uvicorn.protocols.http.auto \
    --hidden-import uvicorn.protocols.websockets \
    --hidden-import uvicorn.protocols.websockets.auto \
    --hidden-import uvicorn.lifespan \
    --hidden-import uvicorn.lifespan.on \
    "${PYINSTALLER_SIGNING_ARGS[@]}" \
    "$SCRIPT_DIR/server.py"

BINARY_PATH="$DIST_DIR/$APP_NAME"
if [[ -f "$BINARY_PATH" ]]; then
    SIZE="$(du -sh "$BINARY_PATH" | cut -f1)"
    echo ""
    echo "Build complete: $BINARY_PATH ($SIZE)"

    if [[ "$CODE_SIGNING_ALLOWED" == "YES" ]]; then
        if [[ -z "$CODE_SIGN_IDENTITY" ]]; then
            echo "error: CODE_SIGNING_ALLOWED=YES requires CODE_SIGN_IDENTITY." >&2
            exit 1
        fi
        echo "Signing standalone server with '$CODE_SIGN_IDENTITY'..."
        codesign --force --options runtime --timestamp \
            --entitlements "$ENTITLEMENTS_PATH" \
            --sign "$CODE_SIGN_IDENTITY" "$BINARY_PATH"
        codesign --verify --strict --verbose=2 "$BINARY_PATH"
        CODESIGN_DETAILS="$(codesign -dv --verbose=2 "$BINARY_PATH" 2>&1)"
        SIGNING_AUTHORITY="$(printf '%s\n' "$CODESIGN_DETAILS" | awk -F= '/^Authority=/ && !found {print $2; found=1}')"
    else
        SIGNING_AUTHORITY="<unsigned>"
    fi

    if [[ "$RUN_TRANSCRIPTION_SMOKE_TEST" == "YES" ]]; then
        echo "Running packaged transcription smoke test..."
        SERVER_BINARY="$BINARY_PATH" "$SCRIPT_DIR/smoke_test.sh"
    else
        echo "Packaged transcription smoke test NOT RUN (RUN_TRANSCRIPTION_SMOKE_TEST=$RUN_TRANSCRIPTION_SMOKE_TEST)."
    fi

    mkdir -p "$OUTPUT_DIR"
    VERSIONED_DMG_NAME="$APP_NAME-v$VERSION-macos-arm64.dmg"
    STABLE_DMG_NAME="$APP_NAME-macos-arm64.dmg"
    VERSIONED_DMG_PATH="$OUTPUT_DIR/$VERSIONED_DMG_NAME"
    STABLE_DMG_PATH="$OUTPUT_DIR/$STABLE_DMG_NAME"
    STAGING_DIR="$SCRIPT_DIR/build/release-staging"

    echo "Packaging standalone release disk image..."
    rm -rf "$STAGING_DIR"
    mkdir -p "$STAGING_DIR"
    ditto "$BINARY_PATH" "$STAGING_DIR/$APP_NAME"
    SOURCE_SIZE_KB="$(du -sk "$STAGING_DIR" | awk '{print $1}')"
    DMG_SIZE_KB="$((SOURCE_SIZE_KB + 65536))"
    hdiutil create \
        -volname "BugNarrator Local Transcription" \
        -srcfolder "$STAGING_DIR" \
        -size "${DMG_SIZE_KB}k" \
        -ov \
        -format UDZO \
        "$VERSIONED_DMG_PATH" >/dev/null

    if [[ "$CODE_SIGNING_ALLOWED" == "YES" ]]; then
        echo "Signing standalone server DMG with '$CODE_SIGN_IDENTITY'..."
        codesign --force --timestamp --sign "$CODE_SIGN_IDENTITY" "$VERSIONED_DMG_PATH"
        codesign --verify --strict --verbose=2 "$VERSIONED_DMG_PATH"
    fi

    if [[ "$NOTARIZE" == "YES" ]]; then
        echo "Submitting standalone server DMG for notarization..."
        xcrun notarytool submit "$VERSIONED_DMG_PATH" \
            --keychain-profile "$NOTARY_PROFILE" \
            --wait
        xcrun stapler staple "$VERSIONED_DMG_PATH"
        xcrun stapler validate "$VERSIONED_DMG_PATH"
    fi

    cp "$VERSIONED_DMG_PATH" "$STABLE_DMG_PATH"

    (
        cd "$OUTPUT_DIR"
        shasum -a 256 "$VERSIONED_DMG_NAME" >"$VERSIONED_DMG_NAME.sha256"
        shasum -a 256 "$STABLE_DMG_NAME" >"$STABLE_DMG_NAME.sha256"
    )

    PROVENANCE_PATH="$OUTPUT_DIR/$VERSIONED_DMG_NAME.provenance.txt"
    {
        echo "artifact: $VERSIONED_DMG_NAME"
        echo "version: $VERSION"
        echo "commit: $RELEASE_COMMIT"
        echo "tag: ${RELEASE_TAG:-<none>}"
        echo "tree_state: $RELEASE_TREE_STATE"
        echo "architecture: $ARCH"
        echo "python: $PYTHON_VERSION"
        echo "parakeet_mlx: 0.5.1"
        echo "pyinstaller: $PYINSTALLER_VERSION"
        echo "dependency_lock_sha256: $(shasum -a 256 "$REQUIREMENTS_LOCK" | awk '{print $1}')"
        echo "signing_authority: $SIGNING_AUTHORITY"
        echo "notarized: $NOTARIZE"
        echo "transcription_smoke_test: $RUN_TRANSCRIPTION_SMOKE_TEST"
        echo "public_release: $PUBLIC_RELEASE"
    } >"$PROVENANCE_PATH"

    if [[ "$PUBLIC_RELEASE" == "YES" ]]; then
        codesign --verify --strict --verbose=2 "$BINARY_PATH"
        if [[ "$SIGNING_AUTHORITY" != Developer\ ID\ Application:* ]]; then
            echo "error: public standalone artifact is not Developer ID signed." >&2
            exit 1
        fi
        EXECUTABLE_MEMORY_ENTITLEMENT="$(
            codesign -d --entitlements :- "$BINARY_PATH" 2>/dev/null \
                | python3 -c 'import plistlib, sys; print(str(plistlib.loads(sys.stdin.buffer.read()).get("com.apple.security.cs.allow-unsigned-executable-memory", False)).lower())'
        )"
        if [[ "$EXECUTABLE_MEMORY_ENTITLEMENT" != "true" ]]; then
            echo "error: public standalone artifact is missing its required executable-memory entitlement." >&2
            exit 1
        fi
        codesign --verify --strict --verbose=2 "$VERSIONED_DMG_PATH"
        xcrun stapler validate "$VERSIONED_DMG_PATH"
        echo "PUBLIC_RELEASE checks passed for the standalone transcription server."
    fi

    echo "Versioned DMG: $VERSIONED_DMG_PATH"
    echo "Stable DMG: $STABLE_DMG_PATH"
    echo "Provenance: $PROVENANCE_PATH"
else
    echo "error: build failed, binary not found at $BINARY_PATH" >&2
    exit 1
fi
