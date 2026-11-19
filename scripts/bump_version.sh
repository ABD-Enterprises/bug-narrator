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
    echo "error: build number must be a number, got '$NEW_BUILD'" >&2
    exit 2
fi

TODAY="$(date +%Y-%m-%d)"

# The bump rewrites four files that have to agree with each other, so it
# refuses to run on a tree that already carries changes: the bump would be
# mixed with somebody else's work. Untracked files are not a problem — they
# are not part of what the bump writes.
#
# This guard stops the bump from mixing with existing work. It does not make
# the four files atomic as a set: a failure part-way through can still leave
# the sources inconsistent with each other, and that tree has to be brought
# back by hand. What the writes below do guarantee is that each file is
# replaced whole.
# The git environment is cleared for these calls. An inherited GIT_DIR or
# GIT_WORK_TREE would make the guard consult another repository, and a clean
# one would let a dirty tree through. The answer is read from the output as
# well as the exit status, because "true" is what says the tree is a work tree.
if [[ "$(env -u GIT_DIR -u GIT_WORK_TREE git rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]]; then
    echo "error: the bump needs a git checkout so it can tell whether the tree is clean." >&2
    exit 1
fi
# The exit status is checked, not swallowed: a git status that fails must not
# read as a clean tree.
status="$(mktemp)"
if ! env -u GIT_DIR -u GIT_WORK_TREE git status --porcelain --untracked-files=no >"$status"; then
    rm -f "$status"
    echo "error: git status failed, so the bump cannot tell whether the tree is clean." >&2
    exit 1
fi
if [[ -s "$status" ]]; then
    echo "error: the working tree has uncommitted changes; commit or stash them before bumping." >&2
    cat "$status" >&2
    rm -f "$status"
    exit 1
fi
rm -f "$status"

# Writes a file through a temporary file in the same directory and renames it
# over the target, so a reader never sees a half-written file and a failure
# leaves the previous contents in place.
# The temporary files this shell creates are removed when the script exits.
# The handler keeps the status it was called with: an exit trap's last command
# would otherwise become the script's exit status.
#
# A signal does not stop the bump in the same way. An interrupt (SIGINT) does
# not: bash does not run an interrupt trap while it waits for a foreground
# child, and the bump spends its time waiting for one, so the bump runs to the
# end and leaves the tree fully bumped. A termination signal (SIGTERM) does
# stop it, and can leave the tree half bumped, which the version consistency
# check catches.
TEMPORARY_FILES=()
cleanup_temporaries() {
    local status=$?
    local temporary
    for temporary in "${TEMPORARY_FILES[@]+"${TEMPORARY_FILES[@]}"}"; do
        [[ -n "$temporary" ]] && rm -f "$temporary"
    done
    return "$status"
}
trap cleanup_temporaries EXIT

write_atomically() {
    local target="$1"
    shift
    local temporary
    temporary="$(mktemp "${target}.XXXXXX")"
    TEMPORARY_FILES+=("$temporary")
    # The temporary file is private to its owner until it is renamed, so it
    # takes the mode of the file it replaces rather than a fixed one.
    mode=""
    if [[ -e "$target" ]]; then
        # The mode is read with python, which the script already needs, so it is
        # the same on every platform and cannot answer with anything but a mode.
        mode="$(python3 -c 'import os, stat, sys; print(format(stat.S_IMODE(os.stat(sys.argv[1]).st_mode), "o"))' "$target" 2>/dev/null || true)"
    fi
    if [[ "$mode" =~ ^[0-7]{3,4}$ ]]; then
        chmod "$mode" "$temporary"
    else
        if [[ -e "$target" ]]; then
            echo "warning: could not read the mode of $target; the new file gets the default mode." >&2
        fi
        chmod 644 "$temporary"
    fi
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

active = active_path.read_text()
body = active.split("## Unreleased", 1)[1].strip()

archive = archive_path.read_text().rstrip()
heading_end = archive.find("\n## ")
section = f"## {version} - {today}\n\n{body}\n"
if heading_end == -1:
    updated_archive = f"{archive}\n\n{section}"
else:
    updated_archive = f"{archive[:heading_end].rstrip()}\n\n{section}\n{archive[heading_end + 1:].lstrip()}"

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
        temporary = handle.name
        try:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        except BaseException:
            os.unlink(temporary)
            raise
    try:
        # The temporary file keeps the mode of the file it replaces.
        os.chmod(temporary, path.stat().st_mode & 0o7777 if path.exists() else 0o644)
        os.replace(temporary, path)
    except BaseException:
        os.unlink(temporary)
        raise


write_atomically(archive_path, updated_archive)
write_atomically(active_path, "# Changelog\n\n## Unreleased\n")
PY

echo "Bumped to $NEW_VERSION (build $NEW_BUILD)."
echo "Verifying consistency..."
bash "$ROOT_DIR/scripts/check_version_consistency.sh"
