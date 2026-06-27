#!/usr/bin/env bash
#
# Fails if the app version is not consistent across its sources of truth:
#   - VERSION                              (human-facing marketing version)
#   - project.yml MARKETING_VERSION        (XcodeGen → Info.plist CFBundleShortVersionString)
#   - project.yml CURRENT_PROJECT_VERSION  (build number; must be a positive integer)
#   - CHANGELOG.md latest released heading  (first "## X.Y.Z" below any "## Unreleased")
#
# VERSION is the source of truth. Run scripts/bump_version.sh to change it; this
# check guards against the three files drifting apart (e.g. a release shipping
# with a stale VERSION file).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
    echo "error: $*" >&2
    exit 1
}

[[ -f VERSION ]] || fail "VERSION file is missing"
VERSION_FILE_VALUE="$(tr -d '[:space:]' < VERSION)"
[[ -n "$VERSION_FILE_VALUE" ]] || fail "VERSION file is empty"

MARKETING_VERSION="$(awk -F': *' '/^[[:space:]]*MARKETING_VERSION:/ {print $2; exit}' project.yml | tr -d '[:space:]')"
CURRENT_PROJECT_VERSION="$(awk -F': *' '/^[[:space:]]*CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml | tr -d '[:space:]')"

[[ -n "$MARKETING_VERSION" ]] || fail "project.yml is missing MARKETING_VERSION"
[[ -n "$CURRENT_PROJECT_VERSION" ]] || fail "project.yml is missing CURRENT_PROJECT_VERSION"

# Latest released CHANGELOG version: first "## X.Y.Z" heading, skipping "## Unreleased".
CHANGELOG_VERSION="$(awk '
    /^##[[:space:]]+[Uu]nreleased/ { next }
    /^##[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+/ {
        line = $0
        sub(/^##[[:space:]]+/, "", line)
        sub(/[[:space:]].*$/, "", line)
        print line
        exit
    }
' CHANGELOG.md)"

[[ -n "$CHANGELOG_VERSION" ]] || fail "CHANGELOG.md has no released '## X.Y.Z' heading"

errors=0

if [[ "$VERSION_FILE_VALUE" != "$MARKETING_VERSION" ]]; then
    echo "drift: VERSION ($VERSION_FILE_VALUE) != project.yml MARKETING_VERSION ($MARKETING_VERSION)" >&2
    errors=1
fi

if [[ "$VERSION_FILE_VALUE" != "$CHANGELOG_VERSION" ]]; then
    echo "drift: VERSION ($VERSION_FILE_VALUE) != latest released CHANGELOG version ($CHANGELOG_VERSION)" >&2
    errors=1
fi

if ! [[ "$CURRENT_PROJECT_VERSION" =~ ^[0-9]+$ ]]; then
    echo "invalid: project.yml CURRENT_PROJECT_VERSION ($CURRENT_PROJECT_VERSION) is not a positive integer" >&2
    errors=1
fi

if [[ "$errors" -ne 0 ]]; then
    fail "version sources are inconsistent (see above). Run scripts/bump_version.sh to reconcile."
fi

echo "version consistent: $VERSION_FILE_VALUE (build $CURRENT_PROJECT_VERSION)"
