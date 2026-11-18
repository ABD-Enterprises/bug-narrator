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
#      against the real sources, and a disagreement fails the gate. This step
#      is unconditional: nothing in the environment can stand in for the real
#      check, so a drifted tree cannot be hidden.
#   2. Does the check actually catch drift, or has it rotted into one that
#      always agrees? The check is run against a throwaway set of version
#      sources that are deliberately wrong.
#   3. Does the validation actually fail when the contract is broken? A gate
#      that silently stopped running the check would look exactly like a gate
#      that passes, so the validation is run against a genuinely broken tree —
#      a clone whose VERSION disagrees with project.yml — and has to fail, and
#      has to fail because of the version contract.
#
# The third question is answered by running the validation in a clone whose
# version sources are broken. The clone's own gate then stops at its
# real-tree check — the clone's VERSION disagrees with its project.yml — and
# never reaches a proof of its own, so the nesting is one level deep.
#
# That depends on the version check failing, so the gate also carries its own
# limit: VALIDATE_VERSION_GATE_DEPTH says how deep the nesting already is,
# and the gate refuses to clone past MAX_PROOF_DEPTH. A version check that had
# rotted into tolerating the clone's drift would otherwise make each clone's
# validation pass and the gate clone again, without limit. With the limit, it
# makes the gate fail loudly instead, and the proof is never skipped by an
# ambient setting: the limit can only make the gate fail, never pass.
#
# What the third step proves is that the validation fails when the version
# check fails. The validation runs under "set -euo pipefail", so a failing
# check that is not swallowed stops the run; the forms that swallow a failure
# — "|| true", a discarded status, an inverted test — are all caught,
# because the broken tree would then pass.
#
# What no gate can do is survive its own deletion: removing this script from
# scripts/validate.sh removes the check with it. Every check in this
# repository has that property.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

CHECK="$ROOT/scripts/check_version_consistency.sh"

# How many levels of proof may be nested. Each level clones the repository, so
# the limit is also what bounds the cost and the temporary disk a broken
# version check can cost.
readonly MAX_PROOF_DEPTH=2


# ── 1. The real tree must agree right now ─────────────────────────────────
# This is the unconditional step. The check is what the gate exists to
# enforce, so a missing one is a failure rather than a check that quietly
# does nothing, and the check always runs against the real sources.
[[ -x "$CHECK" ]] || fail 'scripts/check_version_consistency.sh is missing or not executable'

VERSION_STATUS_FILE="$ROOT/artifacts/validation/version-status.txt"
mkdir -p "$ROOT/artifacts/validation"

if ! "$CHECK"; then
    printf 'FAIL: the version sources are inconsistent\n' >"$VERSION_STATUS_FILE"
    fail 'the version sources are inconsistent'
fi

# ── 2. The check must catch drift, not merely agree ───────────────────────
# The check reads the version sources from the directory above the script, so
# a throwaway copy of it sees a throwaway set of sources.
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

# The released heading is a source too: a check that stopped comparing it
# would let a release ship a stale version heading unnoticed, so the archive
# has to drift on its own. VERSION agrees with project.yml here, so only the
# archive is wrong. The fixture keeps the shape of the good one — a title and
# a heading — so a check that rejects it has to reject the heading, not the
# shape.
cat >"$workspace/CHANGELOG-archive.md" <<'MARKDOWN'
# Changelog archive

## 9.9.9

- The released version.
MARKDOWN
if "$workspace/scripts/check_version_consistency.sh" >/dev/null 2>&1; then
    fail 'the version check accepted a released heading that does not match VERSION'
fi

cat >"$workspace/CHANGELOG-archive.md" <<'MARKDOWN'
# Changelog archive

## 1.1.0

- The released version.
MARKDOWN

# A build number that is not a number has to be caught too.
sed -i.bak 's/CURRENT_PROJECT_VERSION: 47/CURRENT_PROJECT_VERSION: forty-seven/' "$workspace/project.yml"
if "$workspace/scripts/check_version_consistency.sh" >/dev/null 2>&1; then
    fail 'the version check accepted a build number that is not a number'
fi

# ── 3. The validation has to fail when the contract is broken ──────────────
# This is the step a grep cannot do. Whether the validation runs the check and
# fails on a broken version contract is a property of running it, not of
# looking at it.
#
# The proof covers the committed tree: the clone is made from the repository,
# so it exercises the committed validation, the committed gate and the
# committed check. That is the state CI validates. The working tree's own
# version sources are covered by step 1, which runs against them directly.
depth="${VALIDATE_VERSION_GATE_DEPTH:-0}"
if ! [[ "$depth" =~ ^[0-9]+$ ]]; then
    fail "VALIDATE_VERSION_GATE_DEPTH is not a number: '$depth'"
fi
if (( depth >= MAX_PROOF_DEPTH )); then
    # Reaching the limit means the version check is not failing on a broken
    # tree. That is a defect in the check, and the gate says so rather than
    # letting the nesting grow.
    fail "the version check did not fail on a broken tree at depth $depth; the nesting limit was reached"
fi

# The proof uses a genuinely broken tree rather than a simulated failure: a
# clone of the repository whose VERSION disagrees with project.yml, validated
# in the clone. The clone is what makes it a proof — the validation reads the
# version sources from the tree it is run in, so the check really fails there.
#
# The clone is validated with HEAD as its base ref, so it scans no files and
# reaches the gate quickly. The clone's gate runs one level deeper than this
# one, so the nesting stays inside the limit above.
#
# The proof costs a clone of the repository and a validation run inside it, so
# it grows with the size of the tree.
clone="$workspace/clone"
if ! git clone --quiet --no-local "$ROOT" "$clone" 2>"$workspace/clone-error.txt"; then
    cat "$workspace/clone-error.txt" >&2
    fail 'could not clone the repository to prove the validation fails on a broken version contract'
fi

# A VERSION that disagrees with project.yml and with the released heading.
printf '0.0.0\n' >"$clone/VERSION"

validation_output="$workspace/validation-output.txt"
if env -u AI_VALIDATOR_BASE_REF VALIDATE_VERSION_GATE_DEPTH="$((depth + 1))" \
    "$clone/scripts/validate.sh" HEAD >"$validation_output" 2>&1; then
    fail 'the validation passed although the version contract was broken'
fi

# The validation has to have failed for this reason, not for some other one:
# a base ref it could not diff, for instance.
if ! grep -q 'the version sources are inconsistent' "$validation_output"; then
    cat "$validation_output" >&2
    fail 'the validation failed for another reason than the version contract'
fi

printf 'PASS: VERSION, the app version and the latest release agree\n' | tee "$VERSION_STATUS_FILE"
printf 'PASS: the gate runs the version-consistency check, and the check catches drift\n'
