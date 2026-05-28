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

PYTHON="${PYTHON:-}"
if [[ -z "$PYTHON" ]]; then
    for candidate in python3.12 python3.11 python3; do
        if command -v "$candidate" >/dev/null 2>&1; then
            PYTHON="$(command -v "$candidate")"
            break
        fi
    done
fi

if [[ -z "$PYTHON" ]]; then
    echo "error: python3.12, python3.11, or python3 is required." >&2
    exit 1
fi

PYTHON_VERSION="$("$PYTHON" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
case "$PYTHON_VERSION" in
    3.11|3.12) ;;
    *)
        echo "error: Parakeet local transcription requires Python 3.11 or 3.12; found $PYTHON_VERSION at $PYTHON." >&2
        echo "       Install with: brew install python@3.12" >&2
        echo "       Or rerun with: PYTHON=/opt/homebrew/bin/python3.12 $0" >&2
        exit 1
        ;;
esac

echo "Using Python $PYTHON_VERSION at $PYTHON..."
echo "Creating virtual environment at $VENV_DIR..."
"$PYTHON" -m venv "$VENV_DIR"

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
echo "  Provider: Local (Parakeet)"
echo "  Base URL: http://localhost:8422"
echo "  API Key:  (leave blank)"
