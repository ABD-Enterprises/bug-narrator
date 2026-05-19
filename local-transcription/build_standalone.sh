#!/usr/bin/env bash
set -euo pipefail

# Build a standalone macOS binary of the BugNarrator transcription server.
#
# Output: dist/bugnarrator-transcription (single executable, no Python required)
#
# Prerequisites: Run setup.sh first to create the venv.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${VENV_DIR:-$SCRIPT_DIR/venv}"
DIST_DIR="$SCRIPT_DIR/dist"
APP_NAME="bugnarrator-transcription"

if [[ ! -d "$VENV_DIR" ]]; then
    echo "error: venv not found at $VENV_DIR. Run setup.sh first." >&2
    exit 1
fi

echo "Installing pyinstaller..."
"$VENV_DIR/bin/python" -m pip install pyinstaller --quiet

echo "Building standalone binary..."
"$VENV_DIR/bin/python" -m PyInstaller \
    --name "$APP_NAME" \
    --onefile \
    --noconfirm \
    --clean \
    --distpath "$DIST_DIR" \
    --workpath "$SCRIPT_DIR/build" \
    --specpath "$SCRIPT_DIR/build" \
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
    "$SCRIPT_DIR/server.py"

BINARY_PATH="$DIST_DIR/$APP_NAME"
if [[ -f "$BINARY_PATH" ]]; then
    SIZE="$(du -sh "$BINARY_PATH" | cut -f1)"
    echo ""
    echo "Build complete: $BINARY_PATH ($SIZE)"
    echo ""
    echo "Test it with:"
    echo "  $BINARY_PATH --preload"
    echo ""
    echo "Install it system-wide with:"
    echo "  cp $BINARY_PATH /usr/local/bin/$APP_NAME"
else
    echo "error: build failed, binary not found at $BINARY_PATH" >&2
    exit 1
fi
