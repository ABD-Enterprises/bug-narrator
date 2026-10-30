#!/usr/bin/env bash
#
# Proves that scripts/check-release-environment.sh refuses to let a release
# through when the release environment is not a gate.
#
# The gate is the control the whole release gate exists to provide, and
# nothing else in the repository tested it: the wiring check proves that the
# gate is wired up, not that it decides correctly. This script drives the
# gate against recorded responses from the environment API -- the shapes that
# API can answer with -- and asserts that every degraded shape is refused and
# that the healthy shape is accepted.
#
# It runs as part of scripts/validate.sh, so the gate cannot rot unnoticed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GATE_SCRIPT="scripts/check-release-environment.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT
mkdir -p "$workspace/bin"

# A mock gh that replays recorded responses.
#
# The body of the environment and of its branch policies comes from a file,
# and the status from the environment, so every shape the API can answer with
# is a file this script writes rather than a special case in the mock. The
# `--jq` filters the gate uses are applied here the way jq applies them, so
# the gate is driven with the answers it would really get.
cat >"$workspace/bin/gh" <<'MOCK_GH'
#!/usr/bin/env python3
"""A mock gh that replays recorded responses from the environment API."""
import json
import os
import sys

arguments = sys.argv[1:]
filter_expression = ""
for index, argument in enumerate(arguments):
    if argument == "--jq" and index + 1 < len(arguments):
        filter_expression = arguments[index + 1]

if any("deployment-branch-policies" in argument for argument in arguments):
    body_file = os.environ.get("MOCK_POLICY_BODY", "")
    status = os.environ.get("MOCK_POLICY_STATUS", "200")
elif any("/environments/" in argument for argument in arguments):
    body_file = os.environ.get("MOCK_ENVIRONMENT_BODY", "")
    status = os.environ.get("MOCK_ENVIRONMENT_STATUS", "200")
else:
    sys.stderr.write("mock gh: unexpected call: %s\n" % " ".join(arguments))
    sys.exit(1)

if status != "200":
    if status == "404":
        sys.stderr.write("gh: Not Found (HTTP 404)\n")
    elif status == "403":
        sys.stderr.write("gh: Forbidden (HTTP 403)\n")
    else:
        sys.stderr.write("gh: Server Error (HTTP %s)\n" % status)
    sys.exit(1)

try:
    with open(body_file, encoding="utf-8") as handle:
        body = json.load(handle)
except (OSError, ValueError) as error:
    sys.stderr.write("gh: could not read the recorded response: %s\n" % error)
    sys.exit(1)


def jq_string(value):
    """jq's tostring: null is "null" and the booleans are spelled out."""
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        return repr(value)
    return str(value)


def protection_rules():
    return body.get("protection_rules") or []


def reviewer_rules():
    return [rule for rule in protection_rules() if rule.get("type") == "required_reviewers"]


# The reviewer count is the one call whose answer is a bare number, so it can
# be forced to something that is not one.
if "| length" in filter_expression:
    count = os.environ.get("MOCK_COUNT") or None
    if count is None:
        count = 0
        for rule in reviewer_rules():
            for reviewer in rule.get("reviewers") or []:
                person = reviewer.get("reviewer")
                if person is not None and person.get("id") is not None:
                    count += 1
    sys.stdout.write(str(count))
    warning = os.environ.get("MOCK_WARN")
    if warning:
        sys.stderr.write("warning: %s\n" % warning)
    sys.exit(0)

if "branch_policies" in filter_expression:
    policies = body.get("branch_policies") or []
    sys.stdout.write(
        " | ".join("%s %s" % (jq_string(policy.get("type")), jq_string(policy.get("name"))) for policy in policies)
    )
    sys.exit(0)

if "can_admins_bypass" in filter_expression:
    sys.stdout.write("no" if body.get("can_admins_bypass") is False else "yes")
    sys.exit(0)

if "prevent_self_review" in filter_expression:
    sys.stdout.write(",".join(jq_string(rule.get("prevent_self_review")) for rule in reviewer_rules()))
    sys.exit(0)

sys.stdout.write(",".join(jq_string(rule.get("type")) for rule in protection_rules()))
MOCK_GH
chmod +x "$workspace/bin/gh"

ENVIRONMENT_BODY="$workspace/environment.json"
POLICY_BODY="$workspace/policy.json"

# The environment as the API answers it when it is a gate: a named reviewer,
# the self-review setting declared, no admin bypass and a branch policy that
# admits exactly main.
write_healthy_environment() {
    cat >"$ENVIRONMENT_BODY" <<'JSON'
{
  "id": 1,
  "name": "windows-release",
  "protection_rules": [
    {
      "id": 1,
      "type": "required_reviewers",
      "prevent_self_review": false,
      "reviewers": [
        { "type": "User", "reviewer": { "login": "deffenda", "id": 4432479 } }
      ]
    },
    { "id": 2, "type": "branch_policy" }
  ],
  "can_admins_bypass": false
}
JSON
}

write_healthy_policy() {
    cat >"$POLICY_BODY" <<'JSON'
{
  "total_count": 1,
  "branch_policies": [
    { "type": "branch", "name": "main" }
  ]
}
JSON
}

# Writes the environment body with one rule changed.
write_environment_with() {
    local python_code="$1"
    write_healthy_environment
    python3 - "$ENVIRONMENT_BODY" <<PYTHON
import json
import sys

path = sys.argv[1]
body = json.load(open(path, encoding="utf-8"))
$python_code
json.dump(body, open(path, "w", encoding="utf-8"))
PYTHON
}

# Runs the gate against the recorded responses.
run_gate() {
    (
        export PATH="$workspace/bin:$PATH"
        export RELEASE_ENVIRONMENT="${RELEASE_ENVIRONMENT-windows-release}"
        export GITHUB_REPOSITORY="${GITHUB_REPOSITORY-ABD-Enterprises/bug-narrator}"
        export MOCK_ENVIRONMENT_BODY="$ENVIRONMENT_BODY"
        export MOCK_POLICY_BODY="$POLICY_BODY"
        export MOCK_ENVIRONMENT_STATUS="${MOCK_ENVIRONMENT_STATUS-200}"
        export MOCK_POLICY_STATUS="${MOCK_POLICY_STATUS-200}"
        export MOCK_COUNT="${MOCK_COUNT-}"
        export MOCK_WARN="${MOCK_WARN-}"
        "$ROOT/$GATE_SCRIPT"
    )
}

# Applies the given NAME=value pairs. `run_gate` exports the variables the
# mock reads, so they only have to be set here.
apply_overrides() {
    local assignment name value
    for assignment in "$@"; do
        name="${assignment%%=*}"
        value="${assignment#*=}"
        printf -v "$name" '%s' "$value"
    done
}

# Every degraded shape has to be refused: the gate is the control that keeps
# an ungated release from going out. The extra arguments are exported for the
# mock: a status, a forced count or a warning.
expect_refused_with() {
    local name="$1"
    shift
    if (apply_overrides "$@"; run_gate) >/dev/null 2>&1; then
        fail "the release environment gate accepted $name"
    fi
}

expect_accepted_with() {
    local name="$1"
    shift
    if ! (apply_overrides "$@"; run_gate) >/dev/null 2>&1; then
        fail "the release environment gate refused $name"
    fi
}

expect_refused() {
    expect_refused_with "$1"
}

expect_accepted() {
    expect_accepted_with "$1"
}

write_healthy_environment
write_healthy_policy
expect_accepted "an environment that is a gate"

# The environment does not exist.
expect_refused_with "an environment that does not exist" "MOCK_ENVIRONMENT_STATUS=404"

# The environment cannot be read.
expect_refused_with "an environment the API refuses to read" "MOCK_ENVIRONMENT_STATUS=403"
expect_refused_with "an environment the API fails to read" "MOCK_ENVIRONMENT_STATUS=500"
expect_refused_with "a branch policy list that cannot be read" "MOCK_POLICY_STATUS=404"

# The environment no longer requires a reviewer.
write_environment_with 'body["protection_rules"] = [{"id": 2, "type": "branch_policy"}]'
expect_refused "an environment that requires no reviewer"

# The environment requires a reviewer but names none.
write_environment_with 'body["protection_rules"][0]["reviewers"] = []'
expect_refused "an environment that names no reviewer"

# The reviewer count reads as zero even though the call succeeded and wrote a
# warning: a warning on stderr must not turn "no reviewer is named" into a
# pass. This is the shape that used to slip through.
expect_refused_with "an environment that names no reviewer, with a warning" \
    "MOCK_COUNT=0" "MOCK_WARN=the environment changed"
expect_refused_with "an environment that names no reviewer" "MOCK_COUNT=0"
expect_refused_with "a reviewer count that is not a number" "MOCK_COUNT=not-a-number"

# The reviewer list can be read as a count, with or without a warning.
expect_accepted_with "an environment that names a reviewer, with a warning" \
    "MOCK_COUNT=1" "MOCK_WARN=the environment changed"
expect_accepted_with "an environment that names a reviewer" "MOCK_COUNT=1"

# The self-review setting is not declared.
write_environment_with 'del body["protection_rules"][0]["prevent_self_review"]'
expect_refused "an environment that does not declare prevent_self_review"

write_environment_with 'body["protection_rules"][0]["prevent_self_review"] = None'
expect_refused "an environment whose prevent_self_review is null"

# Administrators can bypass the protection rules.
write_environment_with 'body["can_admins_bypass"] = True'
expect_refused "an environment administrators can bypass"

write_environment_with 'del body["can_admins_bypass"]'
expect_refused "an environment that does not say whether administrators can bypass"

# The environment does not restrict which branch may deploy.
write_environment_with 'body["protection_rules"] = [body["protection_rules"][0]]'
expect_refused "an environment that does not restrict the branch"

# The branch policy admits more than main.
write_healthy_environment
write_healthy_policy
python3 - "$POLICY_BODY" <<'PYTHON'
import json
import sys

path = sys.argv[1]
body = json.load(open(path, encoding="utf-8"))
body["branch_policies"].append({"type": "branch", "name": "develop"})
json.dump(body, open(path, "w", encoding="utf-8"))
PYTHON
expect_refused "an environment that admits a branch besides main"

write_healthy_environment
cat >"$POLICY_BODY" <<'JSON'
{
  "total_count": 1,
  "branch_policies": [
    { "type": "tag", "name": "v1" }
  ]
}
JSON
expect_refused "an environment that admits a tag instead of a branch"

write_healthy_environment
cat >"$POLICY_BODY" <<'JSON'
{
  "total_count": 0,
  "branch_policies": []
}
JSON
expect_refused "an environment with no branch policy"

# The answer is not the shape the API answers with.
write_healthy_environment
printf 'not json at all' >"$ENVIRONMENT_BODY"
expect_refused "an answer that is not JSON"

write_healthy_environment
write_healthy_policy
expect_accepted "an environment that is a gate"

# The gate cannot be told which environment to check.
expect_refused_with "a run that names no environment" "RELEASE_ENVIRONMENT="
expect_refused_with "a run that names no repository" "GITHUB_REPOSITORY="

printf 'PASS: the release environment gate refuses every environment that is not a gate\n'
