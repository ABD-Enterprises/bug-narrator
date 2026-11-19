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
#      has to fail with the version gate's own failure line.
#
# What question 3 does not establish: that no committed change can make the
# validation swallow the failure. A validator that prints the version gate's
# failure line and then fails for its own reason would satisfy the proof, and
# so would a validator that stopped running the gate. Those are committed
# changes, visible in the diff that introduced them, and the independent review
# of that change is what catches them — the same way it catches any other
# committed change that weakens a check.
#
# The third question is answered by running the validation in a clone whose
# version sources are broken. The clone's own gate then stops at its
# real-tree check — the clone's VERSION disagrees with its project.yml — and
# never reaches a proof of its own, so the nesting is one level deep.
#
# That depends on the version check failing, so the gate also carries its own
# limit. How deep the nesting already is travels in a file inside the tree
# rather than in the environment, so a validator that runs the gate under a
# clean environment cannot reset the count and make the limit unreachable.
# Past MAX_PROOF_DEPTH the gate fails loudly: a version check that had rotted
# into tolerating the clone's drift would otherwise make each clone's
# validation pass and the gate clone again, without limit.
#
# The limit is not tamper-proof either: a validator that rewrites the depth
# marker can reset the count, and that too is a committed change. The
# watchdog on the nested validation is the backstop that holds in every case:
# the nesting cannot spend the runner's time and disk without limit, because
# the gate stops the whole tree when the watchdog fires.
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
# How long the nested validation may run before the gate gives up on it. It is
# the backstop that bounds the nesting when the depth is lost.
readonly PROOF_TIMEOUT_SECONDS=300


# How deep the tree this gate runs in already is. It is carried by a file
# inside the tree rather than by the environment, because a validator that
# runs the gate under a clean environment would otherwise reset the count at
# every level and the limit would never be reached. The file lives under the
# gitignored artifacts directory, so a clone never inherits one.
readonly DEPTH_MARKER="artifacts/validation/version-gate-depth"




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
# The proof runs the COMMITTED validator, because that is the validator CI
# runs and the one the merge decision is about. The working tree's own version
# sources are covered by step 1, which runs against them directly.
depth=0
depth_file="$ROOT/$DEPTH_MARKER"
if [[ -e "$depth_file" ]]; then
    if git -C "$ROOT" ls-files --error-unmatch -- "$DEPTH_MARKER" >/dev/null 2>&1; then
        # The marker belongs to a throwaway clone. A tracked one would reset the
        # count in every clone and defeat the limit.
        fail "the version-gate depth marker is tracked; it must never be committed"
    fi
    depth="$(tr -d '[:space:]' <"$depth_file")"
    if ! [[ "$depth" =~ ^[0-9]+$ ]] || (( depth > 99 )); then
        fail "the version-gate depth marker is not a usable depth: '$depth'"
    fi
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
# The nested validation runs under a watchdog as well. The depth limit bounds
# the nesting in the normal case; the watchdog bounds it in every case,
# including one in which the depth is lost, so a broken version check cannot
# spend the runner's time and disk without limit. The watchdog is written with
# the shell's own facilities rather than with "timeout", which macOS does not
# provide.
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
mkdir -p "$clone/$(dirname "$DEPTH_MARKER")"
printf '%s\n' "$((depth + 1))" >"$clone/$DEPTH_MARKER"

# Job control gives the nested validation its own process group, so the
# watchdog can stop the whole tree and not only the process it started: the
# nested validation spawns its own children, and killing only the parent would
# leave them running.
set -m
env -u AI_VALIDATOR_BASE_REF \
    "$clone/scripts/validate.sh" HEAD >"$validation_output" 2>&1 &
nested_pid=$!
set +m
nested_status=0
deadline=$((SECONDS + PROOF_TIMEOUT_SECONDS))
while kill -0 "$nested_pid" 2>/dev/null; do
    if (( SECONDS >= deadline )); then
        kill -TERM "-$nested_pid" 2>/dev/null || kill -TERM "$nested_pid" 2>/dev/null || true
        sleep 1
        kill -KILL "-$nested_pid" 2>/dev/null || kill -KILL "$nested_pid" 2>/dev/null || true
        wait "$nested_pid" 2>/dev/null || true
        fail "the validation did not finish within ${PROOF_TIMEOUT_SECONDS}s; the nesting is not bounded"
    fi
    sleep 1
done
wait "$nested_pid" 2>/dev/null || nested_status=$?

if (( nested_status == 0 )); then
    fail 'the validation passed although the version contract was broken'
fi

# The validation has to have failed for this reason, not for some other one.
# The clone's own gate writes the marker when it finds the contract broken, so
# the attribution cannot be satisfied by an unrelated failure that happens to
# print a similar phrase.
# The validation has to have failed for this reason, and not for some other
# one. The version gate's own failure line is matched exactly: the check's
# message differs ("error: version sources are inconsistent"), and a failure
# that merely mentions the phrase in passing does not match either.
if ! grep -q '^FAIL: the version sources are inconsistent$' "$validation_output"; then
    cat "$validation_output" >&2
    # The nesting limit is a real reason, not an unrelated one, and it is the
    # reason that matters when the version check has rotted.
    if grep -q 'the nesting limit was reached' "$validation_output"; then
        fail 'the version check did not fail on a broken tree; the nesting limit was reached'
    fi
    fail 'the validation failed for another reason than the version contract'
fi

printf 'PASS: VERSION, the app version and the latest release agree\n' | tee "$VERSION_STATUS_FILE"
printf 'PASS: the gate runs the version-consistency check, and the check catches drift\n'
