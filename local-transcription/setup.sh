#!/usr/bin/env bash
set -euo pipefail

# BugNarrator Local Transcription Server — one-time setup
#
# Prerequisites: brew install ffmpeg
#
# This script creates a dedicated Python venv, installs parakeet-mlx and the
# FastAPI server dependencies, and prints the command to start the server.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${VENV_DIR:-$SCRIPT_DIR/venv}"
REQUIREMENTS="$SCRIPT_DIR/requirements.txt"

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "error: ffmpeg is required. Install it with: brew install ffmpeg" >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "error: python3 is required." >&2
    exit 1
fi

echo "Creating virtual environment at $VENV_DIR..."
python3 -m venv "$VENV_DIR"

echo "Installing dependencies..."
"$VENV_DIR/bin/python" -m pip install --upgrade pip --quiet
"$VENV_DIR/bin/python" -m pip install -r "$REQUIREMENTS" --quiet

echo ""
echo "Setup complete."
echo ""
echo "Start the server with:"
echo "  $VENV_DIR/bin/python $SCRIPT_DIR/server.py"
echo ""
echo "Or preload the model at startup (recommended):"
echo "  $VENV_DIR/bin/python $SCRIPT_DIR/server.py --preload"
echo ""
echo "Then configure BugNarrator:"
echo "  Provider: Local-Compatible"
echo "  Base URL: http://localhost:8422"
echo "  API Key:  (leave blank)"
