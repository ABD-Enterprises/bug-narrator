#!/usr/bin/env bash
#
# Refuses to publish when the release environment is not a gate.
#
# A workflow that names an environment that does not exist makes GitHub create
# it with no protection rules at all, so the release would publish with no
# approval and no branch restriction — and nothing would say so.
#
# The check runs twice on purpose. The preflight runs it before a runner is
# reserved, so a broken environment is caught before any build time is spent.
# The publishing job runs it again, because GitHub resolves the environment
# when the job starts: an environment deleted or unprotected in between would
# otherwise be auto-created with no rules and the release would go out
# ungated.
#
# The environment name is not defaulted. The caller has to name the environment
# it deploys to, so a renamed environment can never be checked under the old
# name while the job publishes into an environment with no protection rules.
# `scripts/check-release-environment-wiring.sh` keeps the name this script is
# given and the `environment:` key of the release job from drifting apart.
#
# The repository comes from the environment so the same script serves both
# workflows.

set -euo pipefail

ENVIRONMENT="${RELEASE_ENVIRONMENT:-}"
REPOSITORY="${GITHUB_REPOSITORY:-}"

fail() {
    printf '::error::%s\n' "$*" >&2
    exit 1
}

# The payload of the last call, and the error output of the last failed one.
payload=""
error_output=""

# Reads one endpoint of the environment API.
#
# The payload and the error output are kept apart on purpose. gh writes
# warnings to stderr even when the call succeeds, and a merged stream would
# let that warning change the value the checks below compare against: a
# reviewer count of 0 would read as "0" plus a warning, which is not "0", and
# the check that no reviewer is named would be skipped.
read_api() {
    local endpoint="$1"
    local filter="$2"
    local error_file
    error_file="$(mktemp)"
    if payload="$(gh api "$endpoint" --jq "$filter" 2>"$error_file")"; then
        error_output=""
        rm -f "$error_file"
        return 0
    fi
    error_output="$(cat "$error_file")"
    rm -f "$error_file"
    return 1
}

[[ -n "$ENVIRONMENT" ]] || fail "RELEASE_ENVIRONMENT is not set; cannot tell which environment gates the release."
[[ -n "$REPOSITORY" ]] || fail "GITHUB_REPOSITORY is not set; cannot read the release environment."

environment_api="repos/$REPOSITORY/environments/$ENVIRONMENT"

if ! read_api "$environment_api" '[.protection_rules[]?.type] | join(",")'; then
    fail "The $ENVIRONMENT environment could not be read: $error_output"
fi
rules="$payload"

if [[ "$rules" != *required_reviewers* ]]; then
    fail "The $ENVIRONMENT environment does not require a reviewer; refusing to publish."
fi

# A required-reviewers rule with nobody in it gates nobody: a reviewer who
# loses repository access can be dropped from the list, and an empty list
# leaves the rule satisfied by no one at all.
if ! read_api "$environment_api" '[.protection_rules[]? | select(.type == "required_reviewers") | .reviewers[]? | select(.reviewer != null and .reviewer.id != null)] | length'; then
    fail "The $ENVIRONMENT environment's reviewer list could not be read: $error_output"
fi
# The count is compared as a number, so anything that is not one is refused
# rather than read as a count that happens to be greater than zero.
if [[ ! "$payload" =~ ^[0-9]+$ ]]; then
    fail "The $ENVIRONMENT environment's reviewer count could not be read as a number (\"$payload\"); refusing to publish."
fi
if [[ "$payload" -eq 0 ]]; then
    fail "The $ENVIRONMENT environment requires a reviewer but names none; refusing to publish."
fi

# The reviewer rule also carries prevent_self_review. It has to be declared:
# an absent or null value leaves the platform default in force and nobody can
# tell from the release log whether the requester may approve their own
# release.
#
# This repository has one maintainer, so the approval can be self-issued and
# the setting is reported rather than required to be true — requiring it would
# leave every release unapprovable. When a second maintainer is added, turn
# "Prevent self-review" on for the environment and this check reports it.
if ! read_api "$environment_api" '[.protection_rules[]? | select(.type == "required_reviewers") | .prevent_self_review] | join(",")'; then
    fail "The $ENVIRONMENT environment's self-review setting could not be read: $error_output"
fi
case "$payload" in
    true)
        printf 'The %s environment blocks self-approval of the release.\n' "$ENVIRONMENT"
        ;;
    false)
        printf 'NOTICE: the %s environment lets the requester approve their own release; this repository has one maintainer.\n' "$ENVIRONMENT"
        ;;
    *)
        fail "The $ENVIRONMENT environment does not declare prevent_self_review (read \"$payload\"); refusing to publish."
        ;;
esac

if [[ "$rules" != *branch_policy* ]]; then
    fail "The $ENVIRONMENT environment does not restrict which branch may deploy; refusing to publish."
fi

if ! read_api "$environment_api" 'if .can_admins_bypass == false then "no" else "yes" end'; then
    fail "The $ENVIRONMENT environment's protection rules could not be read: $error_output"
fi
if [[ "$payload" != "no" ]]; then
    fail "The $ENVIRONMENT environment lets administrators bypass its protection rules; refusing to publish."
fi

if ! read_api "$environment_api/deployment-branch-policies" '[.branch_policies[]? | "\(.type) \(.name)"] | join(" | ")'; then
    fail "The $ENVIRONMENT environment's branch policies could not be read: $error_output"
fi
if [[ "$payload" != "branch main" ]]; then
    fail "The $ENVIRONMENT environment admits \"$payload\", not exactly main; refusing to publish."
fi

printf 'The %s environment still gates the release.\n' "$ENVIRONMENT"
