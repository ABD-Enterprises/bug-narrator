#!/usr/bin/env bash
#
# Pins that the validation gate runs the version-consistency check, and that
# the check actually catches drift.
#
# The version sources (VERSION, project.yml's MARKETING_VERSION and the
# latest released heading in the changelog archive) were only compared by the
# release-time scripts, so a drift was found while a release was being cut
# rather than on the push that caused it, and CI reported green while the
# version contract was broken.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

# The gate has to invoke the check. A gate that silently stopped running it
# would look exactly like a gate that passes.
if ! grep -q 'check_version_consistency\.sh' "$ROOT/scripts/validate.sh"; then
    fail 'scripts/validate.sh does not run scripts/check_version_consistency.sh'
fi

CHECK="$ROOT/scripts/check_version_consistency.sh"
[[ -x "$CHECK" ]] || fail 'scripts/check_version_consistency.sh is missing or not executable'

# The check reads the three version sources from the directory above the
# script, so a throwaway copy of it sees a throwaway set of sources.
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT
mkdir -p "$workspace/scripts"
cp "$CHECK" "$workspace/scripts/check_version_consistency.sh"
chmod +x "$workspace/scripts/check_version_consistency.sh"

printf '1.1.0\n' >"$workspace/VERSION"
cat >"$workspace/project.yml" <<'YAML'
name: BugNarrator
options:
  bundleIdPrefix: com.abdenterprises
  deploymentTarget:
    macOS: "14.0"
settings:
  base:
    MARKETING_VERSION: 1.1.0
    CURRENT_PROJECT_VERSION: 47
YAML
cat >"$workspace/CHANGELOG-archive.md" <<'MARKDOWN'
# Changelog archive

## 1.1.0

- The released version.
MARKDOWN

if ! "$workspace/scripts/check_version_consistency.sh" >/dev/null 2>&1; then
    fail 'the version check rejected a consistent set of version sources'
fi

# Drift between VERSION and the app version has to be caught.
printf '1.2.0\n' >"$workspace/VERSION"
if "$workspace/scripts/check_version_consistency.sh" >/dev/null 2>&1; then
    fail 'the version check accepted a VERSION that does not match project.yml'
fi

printf '1.1.0\n' >"$workspace/VERSION"

# A build number that is not a positive integer has to be caught too.
sed -i.bak 's/CURRENT_PROJECT_VERSION: 47/CURRENT_PROJECT_VERSION: forty-seven/' "$workspace/project.yml"
if "$workspace/scripts/check_version_consistency.sh" >/dev/null 2>&1; then
    fail 'the version check accepted a build number that is not a positive integer'
fi

printf 'PASS: the gate runs the version-consistency check, and the check catches drift\n'
