#!/usr/bin/env bash
#
# Pins that the validation gate fails when the version contract is broken.
#
# The version sources (VERSION, project.yml's MARKETING_VERSION and
# CURRENT_PROJECT_VERSION, and the latest released heading in the changelog
# archive) were only compared by the release-time scripts, so a drift was
# found while a release was being cut rather than on the push that caused it,
# and CI reported green while the version contract was broken.
#
# This gate has to answer three questions, and it answers them by running
# things rather than by reading them:
#
#   1. Is the version contract true of the tree right now? The check is run
#      against the real sources, and a disagreement fails the gate.
#   2. Does the check actually catch drift, or has it rotted into one that
#      always agrees? The check is run against a throwaway set of version
#      sources that are deliberately wrong.
#   3. Does the validation actually fail when the check fails? A gate that
#      silently stopped running the check would look exactly like a gate that
#      passes, so the validation is run with a check that always fails and has
#      to fail too.
#
# The third question is answered by running the validation, so the validation
# skips this gate's own third step when it is invoked from here. The
# recursion is broken by VALIDATE_SKIP_VERSION_CHECK_SELF_CHECK, which the
# nested invocation inherits.
#
# What the third step proves is that the validation fails when the check
# fails. The validation runs under "set -euo pipefail", so a failing check
# that is not swallowed stops the run; the forms that swallow a failure —
# "|| true", a discarded status, an inverted test — are all caught, because
# the nested run would then pass.
#
# BUGNARRATOR_VERSION_CHECK substitutes the version check. It exists so the
# third step can inject a check that fails; it is never set in CI.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

DEFAULT_CHECK="$ROOT/scripts/check_version_consistency.sh"

# The substitution is honoured ONLY inside the nested validation this gate
# runs for its own third step. Outside it — in any ordinary validation run —
# the real check always runs, so an inherited environment variable cannot make
# the gate pass while the tree is inconsistent.
if [[ "${VALIDATE_SKIP_VERSION_CHECK_SELF_CHECK:-0}" == "1" && -n "${BUGNARRATOR_VERSION_CHECK:-}" ]]; then
    CHECK="$BUGNARRATOR_VERSION_CHECK"
else
    CHECK="$DEFAULT_CHECK"
fi

# ── 1. The check must exist and be executable ─────────────────────────────
# The check is what the gate exists to enforce, so a missing one is a failure
# rather than a check that quietly does nothing.
[[ -x "$CHECK" ]] || fail "$CHECK is missing or not executable"

# ── 2. The real tree must agree right now ─────────────────────────────────
VERSION_STATUS_FILE="$ROOT/artifacts/validation/version-status.txt"
mkdir -p "$ROOT/artifacts/validation"

if ! "$CHECK"; then
    printf 'FAIL: the version sources are inconsistent\n' >"$VERSION_STATUS_FILE"
    fail 'the version sources are inconsistent'
fi

# ── 3. The check must catch drift, not merely agree ───────────────────────
# The check reads the version sources from the directory above the script, so
# a throwaway copy of it sees a throwaway set of sources.
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT
mkdir -p "$workspace/scripts"
cp "$DEFAULT_CHECK" "$workspace/scripts/check_version_consistency.sh"
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

# ── 4. The validation has to fail when the check fails ────────────────────
# This is the step a grep cannot do. Whether the validation runs the check and
# fails on a broken version contract is a property of running it, not of
# looking at it.
if [[ "${VALIDATE_SKIP_VERSION_CHECK_SELF_CHECK:-0}" != "1" ]]; then
    stub="$workspace/failing-version-check.sh"
    printf '#!/usr/bin/env bash\nexit 1\n' >"$stub"
    chmod +x "$stub"

    validation_output="$workspace/validation-output.txt"
    # AI_VALIDATOR_BASE_REF takes precedence over the argument, so it is cleared:
    # an inherited base ref would make the nested run fail at the diff step
    # instead of at the version contract.
    if env -u AI_VALIDATOR_BASE_REF VALIDATE_SKIP_VERSION_CHECK_SELF_CHECK=1 BUGNARRATOR_VERSION_CHECK="$stub" \
        "$ROOT/scripts/validate.sh" HEAD >"$validation_output" 2>&1; then
        fail 'the validation passed although the version check failed'
    fi

    # The validation has to have failed for this reason, not for some other
    # one: a base ref it could not diff, for instance.
    if ! grep -q 'the version sources are inconsistent' "$validation_output"; then
        cat "$validation_output" >&2
        fail 'the validation failed for another reason than the version check'
    fi
fi

printf 'PASS: VERSION, the app version and the latest release agree\n' | tee "$VERSION_STATUS_FILE"
printf 'PASS: the gate runs the version-consistency check, and the check catches drift\n'
