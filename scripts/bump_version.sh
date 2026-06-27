#!/usr/bin/env bash
#
# Atomically bump the app version across every source of truth and promote the
# CHANGELOG "Unreleased" section. VERSION is the source of truth.
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
    echo "error: build number must be a positive integer, got '$NEW_BUILD'" >&2
    exit 2
fi

TODAY="$(date +%Y-%m-%d)"

# 1. VERSION file.
printf '%s\n' "$NEW_VERSION" > VERSION

# 2. project.yml MARKETING_VERSION + CURRENT_PROJECT_VERSION.
#    Match the leading-whitespace + key form to avoid touching anything else.
/usr/bin/sed -i '' \
    -e "s/^\([[:space:]]*MARKETING_VERSION:[[:space:]]*\).*$/\1$NEW_VERSION/" \
    -e "s/^\([[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*\).*$/\1$NEW_BUILD/" \
    project.yml

# 3. Promote the CHANGELOG "## Unreleased" heading to the new version, leaving a
#    fresh empty Unreleased section above it. Only runs if Unreleased exists.
if grep -qE '^##[[:space:]]+[Uu]nreleased' CHANGELOG.md; then
    awk -v ver="$NEW_VERSION" -v today="$TODAY" '
        !done && /^##[[:space:]]+[Uu]nreleased/ {
            print "## Unreleased"
            print ""
            print "## " ver " - " today
            done = 1
            next
        }
        { print }
    ' CHANGELOG.md > CHANGELOG.md.tmp
    mv CHANGELOG.md.tmp CHANGELOG.md
fi

echo "Bumped to $NEW_VERSION (build $NEW_BUILD)."
echo "Verifying consistency..."
bash "$ROOT_DIR/scripts/check_version_consistency.sh"
