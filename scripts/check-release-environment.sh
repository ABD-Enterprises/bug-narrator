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
# The environment name and the repository come from the environment so the
# same script serves both workflows.

set -euo pipefail

ENVIRONMENT="${RELEASE_ENVIRONMENT:-windows-release}"
REPOSITORY="${GITHUB_REPOSITORY:-}"

fail() {
    printf '::error::%s\n' "$*" >&2
    exit 1
}

[[ -n "$REPOSITORY" ]] || fail "GITHUB_REPOSITORY is not set; cannot read the release environment."

environment_api="repos/$REPOSITORY/environments/$ENVIRONMENT"

if ! rules="$(gh api "$environment_api" --jq '[.protection_rules[]?.type] | join(",")' 2>&1)"; then
    fail "The $ENVIRONMENT environment could not be read: $rules"
fi

if [[ "$rules" != *required_reviewers* ]]; then
    fail "The $ENVIRONMENT environment does not require a reviewer; refusing to publish."
fi

# A required-reviewers rule with nobody in it gates nobody: a reviewer who
# loses repository access can be dropped from the list, and an empty list
# leaves the rule satisfied by no one at all.
if ! reviewers="$(gh api "$environment_api" --jq '[.protection_rules[]? | select(.type == "required_reviewers") | .reviewers[]?] | length' 2>&1)"; then
    fail "The $ENVIRONMENT environment's reviewer list could not be read: $reviewers"
fi
if [[ "$reviewers" == "0" ]]; then
    fail "The $ENVIRONMENT environment requires a reviewer but names none; refusing to publish."
fi

if [[ "$rules" != *branch_policy* ]]; then
    fail "The $ENVIRONMENT environment does not restrict which branch may deploy; refusing to publish."
fi

if ! bypass="$(gh api "$environment_api" --jq 'if .can_admins_bypass == false then "no" else "yes" end' 2>&1)"; then
    fail "The $ENVIRONMENT environment's protection rules could not be read: $bypass"
fi
if [[ "$bypass" != "no" ]]; then
    fail "The $ENVIRONMENT environment lets administrators bypass its protection rules; refusing to publish."
fi

if ! policies="$(gh api "$environment_api/deployment-branch-policies" --jq '[.branch_policies[]? | "\(.type) \(.name)"] | join(" | ")' 2>&1)"; then
    fail "The $ENVIRONMENT environment's branch policies could not be read: $policies"
fi
if [[ "$policies" != "branch main" ]]; then
    fail "The $ENVIRONMENT environment admits \"$policies\", not exactly main; refusing to publish."
fi

printf 'The %s environment still gates the release.\n' "$ENVIRONMENT"
