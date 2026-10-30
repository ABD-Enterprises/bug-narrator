#!/usr/bin/env bash
#
# Keeps the release environment gate and the release job's environment in step.
#
# scripts/check-release-environment.sh has no default environment name: the
# caller names the environment it deploys to, so a renamed environment cannot
# be checked under the old name while the job publishes into an environment
# with no protection rules at all. That only holds while the name the caller
# passes and the `environment:` key of the release job are the same
# environment, so this check compares them for every workflow that runs the
# check.
#
# It also proves itself: a drifted name has to be rejected, or the check would
# be decoration.
#
# It runs as part of scripts/validate.sh, so a drifted name fails the gate
# before a release is dispatched rather than during one.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CHECK_SCRIPT_NAME="scripts/check-release-environment.sh"
RELEASE_WORKFLOWS=(
  ".github/workflows/windows-tester-release.yml"
  ".github/workflows/local-transcription-windows.yml"
)

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

# Prints the distinct values of `KEY: value` lines in a file, one per line.
# A file without such a line yields no output, which is a valid answer here:
# the caller decides whether a missing value is a problem.
read_values() {
    local file="$1"
    local key="$2"
    local found=""

    # The exit status is checked explicitly: inside a process substitution git's
    # and grep's exit status is discarded, so a failed listing would read as
    # "no values" and the caller would compare two empty strings.
    if ! found="$(grep -oE "^[[:space:]]*${key}:[[:space:]]*[A-Za-z0-9._-]+" "$file" 2>&1)"; then
        if [[ -n "$found" ]]; then
            printf 'ERROR: could not read the %s values from %s: %s\n' "$key" "$file" "$found" >&2
            return 1
        fi
        found=""
    fi

    # sed drops the empty lines rather than grep: grep exits 1 when it filters
    # out every line, and with pipefail that would fail the whole listing for
    # a file that simply has no such key.
    printf '%s\n' "$found" \
        | sed -E "s/^[[:space:]]*${key}:[[:space:]]*//" \
        | sed -e '/^[[:space:]]*$/d' \
        | sort -u
}

# Fails when the tree does not hold a coherent release environment gate.
check_tree() {
    local root="$1"
    local check_script="$root/$CHECK_SCRIPT_NAME"
    local workflow_dir="$root/.github/workflows"

    [[ -f "$check_script" ]] || fail "$CHECK_SCRIPT_NAME is missing in $root."
    [[ -d "$workflow_dir" ]] || fail "$root has no .github/workflows directory."

    # The check script must not name an environment itself. A baked-in default
    # is exactly what would let a renamed environment be checked under the old
    # name while the job deployed to an unprotected one.
    if grep -qE 'windows-release' "$check_script"; then
        fail "$CHECK_SCRIPT_NAME names an environment itself; the caller must name it with RELEASE_ENVIRONMENT."
    fi

    # The two release workflows have to exist and have to run the gate. A
    # workflow that stopped running it would publish into an environment
    # nobody checked.
    local workflow
    for workflow in "${RELEASE_WORKFLOWS[@]}"; do
        [[ -f "$root/$workflow" ]] || fail "$workflow is missing in $root."
        if ! grep -qF -- "$CHECK_SCRIPT_NAME" "$root/$workflow"; then
            fail "$workflow does not run $CHECK_SCRIPT_NAME; the release environment gate would never run there."
        fi
    done

    # Every workflow that runs the gate has to name the environment the same
    # way, including any workflow added later.
    local workflows=""
    if ! workflows="$(grep -rlF -- "$CHECK_SCRIPT_NAME" "$workflow_dir" 2>&1)"; then
        if [[ -z "$workflows" ]]; then
            fail "no workflow runs $CHECK_SCRIPT_NAME; the release environment gate would never run."
        fi
        fail "could not list the workflows that run $CHECK_SCRIPT_NAME: $workflows"
    fi

    while IFS= read -r workflow; do
        [[ -n "$workflow" ]] || continue

        local checked deployed
        if ! checked="$(read_values "$workflow" RELEASE_ENVIRONMENT)"; then
            fail "could not read the RELEASE_ENVIRONMENT values from $workflow."
        fi
        if ! deployed="$(read_values "$workflow" environment)"; then
            fail "could not read the environment keys from $workflow."
        fi

        if [[ -z "$checked" ]]; then
            fail "$workflow runs $CHECK_SCRIPT_NAME without naming the environment (RELEASE_ENVIRONMENT)."
        fi
        if [[ -z "$deployed" ]]; then
            fail "$workflow runs $CHECK_SCRIPT_NAME but no job declares an environment."
        fi
        if [[ "$(printf '%s\n' "$checked" | wc -l | tr -d ' ')" != "1" ]]; then
            fail "$workflow names more than one environment for the release gate: $checked"
        fi
        if [[ "$(printf '%s\n' "$deployed" | wc -l | tr -d ' ')" != "1" ]]; then
            fail "$workflow declares more than one environment: $deployed"
        fi
        if [[ "$checked" != "$deployed" ]]; then
            fail "$workflow checks the release environment \"$checked\" but deploys to \"$deployed\"."
        fi
    done <<<"$workflows"
}

check_tree "$ROOT"

# Prove the check catches drift, on a throwaway copy of the tree so the
# repository is never modified.
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT
mkdir -p "$workspace/scripts" "$workspace/.github/workflows"
cp "$ROOT/$CHECK_SCRIPT_NAME" "$workspace/scripts/"
for workflow in "${RELEASE_WORKFLOWS[@]}"; do
    cp "$ROOT/$workflow" "$workspace/$workflow"
done

# A name that no longer matches the job's environment has to be caught.
sed -i.bak 's/RELEASE_ENVIRONMENT: windows-release/RELEASE_ENVIRONMENT: windows-release-old/' \
    "$workspace/.github/workflows/windows-tester-release.yml"
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check accepted a release environment name that does not match the job environment'
fi
cp "$ROOT/.github/workflows/windows-tester-release.yml" "$workspace/.github/workflows/windows-tester-release.yml"

# A workflow that runs the check without naming the environment has to be caught.
sed -i.bak '/RELEASE_ENVIRONMENT: windows-release/d' \
    "$workspace/.github/workflows/local-transcription-windows.yml"
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check accepted a release workflow that does not name the environment'
fi
cp "$ROOT/.github/workflows/local-transcription-windows.yml" "$workspace/.github/workflows/local-transcription-windows.yml"

# A release workflow that stopped running the gate has to be caught.
sed -i.bak '/check-release-environment.sh/d' \
    "$workspace/.github/workflows/local-transcription-windows.yml"
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check accepted a release workflow that does not run the environment gate'
fi
cp "$ROOT/.github/workflows/local-transcription-windows.yml" "$workspace/.github/workflows/local-transcription-windows.yml"

# A baked-in environment name in the check script has to be caught.
printf '\n# windows-release\n' >>"$workspace/$CHECK_SCRIPT_NAME"
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check accepted a check script that names an environment itself'
fi

printf 'PASS: the release environment gate checks the same environment the release job deploys to\n'
