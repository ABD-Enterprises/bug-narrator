#!/usr/bin/env bash
#
# Refreshes the vendored Semgrep ruleset the validation gate scans with.
#
# The gate scans with the rules in semgrep/semgrep-auto.yaml rather than with
# whatever the registry serves that day, so a scan of the same commit looks
# for the same things tomorrow. This script is how the rules are refreshed: it
# downloads the registry's payload, drops the rules that cannot be published,
# and records the payload's hash in the header.
#
# The secret-detection rules (generic.secrets.*) are not vendored. Their
# example values are shaped like real credentials — a Slack webhook URL, an
# AWS key id — and GitHub's push protection refuses a push that contains them,
# which is the right answer for a credential and the wrong one for a
# detection rule. This repository is public and already covered by GitHub's
# secret scanning and push protection, so the rules would add nothing here.
#
# Run it deliberately, read the diff, and commit the result. A rule set that
# moves under a pull request is a scan nobody can reproduce, which is what
# the vendored copy is there to prevent.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RULES_URL="https://semgrep.dev/c/auto"
TARGET="semgrep/semgrep-auto.yaml"
EXCLUDED_PREFIX="generic.secrets."

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

command -v python3 >/dev/null 2>&1 || fail "python3 is required to refresh the vendored ruleset."
command -v curl >/dev/null 2>&1 || fail "curl is required to refresh the vendored ruleset."

workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT

if ! curl --fail --silent --show-error --location "$RULES_URL" --output "$workspace/payload.yaml"; then
    fail "could not download the ruleset from $RULES_URL."
fi

if [[ ! -s "$workspace/payload.yaml" ]]; then
    fail "the downloaded ruleset is empty."
fi

if ! head -n 1 "$workspace/payload.yaml" | grep -q '^rules:'; then
    fail "the downloaded payload does not look like a Semgrep rule set."
fi

# Drop the rules that cannot be published, and report the counts.
counts="$(python3 - "$workspace/payload.yaml" "$workspace/filtered.yaml" "$EXCLUDED_PREFIX" <<'PY'
import sys

source, target, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(source, encoding="utf-8").read().split("\n")

head = []
index = 0
while index < len(lines) and not lines[index].startswith("- id: "):
    head.append(lines[index])
    index += 1

blocks = []
current = []
while index < len(lines):
    line = lines[index]
    if line.startswith("- id: ") and current:
        blocks.append(current)
        current = [line]
    else:
        current.append(line)
    index += 1
if current:
    blocks.append(current)

kept = [block for block in blocks if not block[0].startswith("- id: " + prefix)]
excluded = len(blocks) - len(kept)
if not kept:
    print("the filtered rule set is empty")
    sys.exit(1)

with open(target, "w", encoding="utf-8") as handle:
    handle.write("\n".join(head + [line for block in kept for line in block]))

print(f"{len(kept)} {excluded}")
PY
)" || fail "could not filter the downloaded ruleset."
kept_count="${counts%% *}"
excluded_count="${counts##* }"

digest="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$workspace/filtered.yaml")"

cat >"$workspace/header.txt" <<HEADER
# The Semgrep ruleset the validation gate scans with, vendored so the scan
# cannot change under it: the registry serves mutable rules, and a rule set
# that moves between two runs is a scan nobody can reproduce.
#
# Source: https://semgrep.dev/c/auto (identical to https://semgrep.dev/c/p/default)
# Retrieved: $(date -u +%Y-%m-%d)
# Rules vendored: ${kept_count} (${excluded_count} secret-detection rules under
#   ${EXCLUDED_PREFIX} are not vendored: their example values are shaped like
#   real credentials and GitHub's push protection refuses a push that contains
#   them, and this repository already has GitHub's secret scanning)
# sha256 of the payload below the header: ${digest}
#
# Refresh it with scripts/update-semgrep-rules.sh, which records the new
# hash in the header. Do not edit the rules by hand.
HEADER

mkdir -p "$(dirname "$TARGET")"
cat "$workspace/header.txt" "$workspace/filtered.yaml" >"$TARGET"

printf 'Refreshed %s\n  rules vendored: %s (excluded: %s)\n  payload sha256: %s\n' \
    "$TARGET" "$kept_count" "$excluded_count" "$digest"
