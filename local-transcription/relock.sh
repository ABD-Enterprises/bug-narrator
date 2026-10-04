#!/usr/bin/env bash
set -euo pipefail

# BugNarrator Local Transcription Server — regenerate the hash-locked builds
#
# Run after changing any pin in requirements.txt, requirements-standalone.in or
# requirements-windows.in. Dependabot bumps those pins but not the locks below,
# and the packaged runtimes install only from the locks.
#
# Each command matches the one uv records in that lock's header, run from the
# same directory, so a regenerated lock moves only where a pin moved.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v uv >/dev/null 2>&1; then
    echo "error: uv is required. Install it with: brew install uv" >&2
    exit 1
fi

cd "$ROOT_DIR"
uv pip compile local-transcription/requirements-standalone.in \
    --output-file local-transcription/requirements-standalone.lock \
    --python-version 3.12 --generate-hashes --only-binary=:all: --quiet

cd "$SCRIPT_DIR"
uv pip compile requirements-windows.in --output-file requirements-windows.lock \
    --python-version 3.12 --python-platform x86_64-pc-windows-msvc \
    --generate-hashes --only-binary=:all: --quiet
uv pip compile requirements-windows.in --output-file requirements-windows-arm64.lock \
    --python-version 3.12 --python-platform aarch64-pc-windows-msvc \
    --generate-hashes --only-binary=:all: --quiet

echo "Regenerated requirements-standalone.lock, requirements-windows.lock and requirements-windows-arm64.lock."
