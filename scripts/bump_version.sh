#!/usr/bin/env bash
#
# Atomically bump the app version across every source of truth and move the
# CHANGELOG "Unreleased" section into CHANGELOG-archive.md. VERSION is the
# source of truth.
#
# Usage:
#   scripts/bump_version.sh <marketing-version> [build-number]
#
#   <marketing-version>  e.g. 1.0.40 (X.Y.Z)
#   [build-number]       CFBundleVersion / CURRENT_PROJECT_VERSION. Defaults to
#                        the current build number + 1 (build numbers only need to
#                        be monotonic, so they are not derived from the version).
#
# After bumping, scripts/check_version_consistency.sh should pass.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -lt 1 ]]; then
    echo "usage: scripts/bump_version.sh <marketing-version> [build-number]" >&2
    exit 2
fi

# The bump rewrites four files that have to agree with each other, so it
# refuses to run on a tree that already carries changes: the bump would be
# mixed with somebody else's work, and a failure partway through would leave
# a half-bumped tree behind. Untracked files are not a problem — they are not
# part of what the bump writes.
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "error: the working tree has uncommitted changes; commit or stash them before bumping." >&2
    git status --short --untracked-files=no >&2
    exit 1
fi

NEW_VERSION="$1"
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: marketing version must be X.Y.Z, got '$NEW_VERSION'" >&2
    exit 2
fi

CURRENT_BUILD="$(awk -F': *' '/^[[:space:]]*CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml | tr -d '[:space:]')"
if [[ $# -ge 2 ]]; then
    NEW_BUILD="$2"
else
    NEW_BUILD=$(( CURRENT_BUILD + 1 ))
fi
if ! [[ "$NEW_BUILD" =~ ^[0-9]+$ ]]; then
    echo "error: build number must be a positive integer, got '$NEW_BUILD'" >&2
    exit 2
fi

TODAY="$(date +%Y-%m-%d)"

# Writes a file through a temporary file in the same directory and renames it
# over the target, so a reader never sees a half-written file and a failure
# leaves the previous contents in place. The command has to write to stdout.
write_atomically() {
    local target="$1"
    shift
    local temporary
    temporary="$(mktemp "${target}.XXXXXX")"
    # The temporary file is private to its owner until it is renamed; the
    # files this script writes are ordinary repository files.
    chmod 644 "$temporary"
    if ! "$@" >"$temporary"; then
        rm -f "$temporary"
        return 1
    fi
    mv -f "$temporary" "$target"
}

# Validate every changelog precondition before changing any version source.
python3 <<'PY'
from pathlib import Path

active_path = Path("CHANGELOG.md")
archive_path = Path("CHANGELOG-archive.md")
if not active_path.is_file():
    raise SystemExit("error: CHANGELOG.md is missing")
if not archive_path.is_file():
    raise SystemExit("error: CHANGELOG-archive.md is missing")

active = active_path.read_text()
marker = "## Unreleased"
if marker not in active:
    raise SystemExit("error: CHANGELOG.md is missing ## Unreleased")

body = active.split(marker, 1)[1].strip()
if not body:
    raise SystemExit("error: CHANGELOG.md Unreleased section is empty")
if body.startswith("## ") or "\n## " in body:
    raise SystemExit("error: CHANGELOG.md contains a released section; move it to CHANGELOG-archive.md")
PY

# 1. VERSION file.
write_atomically VERSION printf '%s\n' "$NEW_VERSION"

# 2. project.yml MARKETING_VERSION + CURRENT_PROJECT_VERSION.
#    Match the leading-whitespace + key form to avoid touching anything else.
write_atomically project.yml /usr/bin/sed \
    -e "s/^\([[:space:]]*MARKETING_VERSION:[[:space:]]*\).*$/\1$NEW_VERSION/" \
    -e "s/^\([[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*\).*$/\1$NEW_BUILD/" \
    project.yml

# 3. Archive the Unreleased body and reset the active changelog. The active file
#    intentionally contains no released sections so agent reads stay bounded.
python3 - "$NEW_VERSION" "$TODAY" <<'PY'
import os
import sys
import tempfile
from pathlib import Path

version, today = sys.argv[1:]
active_path = Path("CHANGELOG.md")
archive_path = Path("CHANGELOG-archive.md")


def write_atomically(path: Path, text: str) -> None:
    """Write through a temporary file in the same directory and rename it.

    A reader never sees a half-written file, and a failure leaves the
    previous contents in place.
    """
    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=path.parent,
        prefix=path.name + ".",
        suffix=".tmp",
        delete=False,
    ) as handle:
        handle.write(text)
        temporary = Path(handle.name)
    os.chmod(temporary, 0o644)
    temporary.replace(path)


active = active_path.read_text()
body = active.split("## Unreleased", 1)[1].strip()

archive = archive_path.read_text().rstrip()
heading_end = archive.find("\n## ")
section = f"## {version} - {today}\n\n{body}\n"
if heading_end == -1:
    updated_archive = f"{archive}\n\n{section}"
else:
    updated_archive = f"{archive[:heading_end].rstrip()}\n\n{section}\n{archive[heading_end + 1:].lstrip()}"

write_atomically(archive_path, updated_archive)
write_atomically(active_path, "# Changelog\n\n## Unreleased\n")
PY

echo "Bumped to $NEW_VERSION (build $NEW_BUILD)."
echo "Verifying consistency..."
bash "$ROOT_DIR/scripts/check_version_consistency.sh"
