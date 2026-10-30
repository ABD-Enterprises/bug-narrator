#!/usr/bin/env bash
#
# Pins that the validation gate scans with a pinned image and a pinned rule
# set, and proves that the pin is still in place.
#
# The Semgrep image used to be a mutable tag and the rules came from the
# registry at run time, so an upstream tag move or a registry compromise
# changed what ran in CI, and a scan of the same commit did not look for the
# same things twice. The image is now addressed by digest and the rules are
# vendored in the repository.
#
# It takes an optional repository root, so it can be pointed at a copy of the
# tree: the proof that the check catches an unpinned scan needs one.

set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

check_tree() {
    local root="$1"

    local validate="$root/scripts/validate.sh"
    local ruleset="$root/semgrep/semgrep-auto.yaml"

    [[ -f "$validate" ]] || fail "scripts/validate.sh is missing."
    [[ -f "$ruleset" ]] || fail "the vendored ruleset semgrep/semgrep-auto.yaml is missing."

    # Every image reference has to carry a digest. A versioned tag alone
    # still moves.
    local references
    if ! references="$(grep -oE 'semgrep/semgrep:[^"'"'"'[:space:]]+' "$validate" 2>&1)"; then
        if [[ -n "$references" ]]; then
            fail "could not read the Semgrep image references: $references"
        fi
        references=""
    fi
    if [[ -z "$references" ]]; then
        fail "scripts/validate.sh does not name the Semgrep image at all."
    fi
    local reference
    while IFS= read -r reference; do
        [[ -n "$reference" ]] || continue
        if [[ ! "$reference" =~ @sha256:[0-9a-f]{64}$ ]]; then
            fail "the Semgrep image \"$reference\" is not pinned by digest."
        fi
    done <<<"$references"

    # The rules have to come from the repository, not from the registry.
    if grep -q -- '--config=auto' "$validate"; then
        fail "scripts/validate.sh still scans with the registry's current rules."
    fi
    if ! grep -q 'semgrep/semgrep-auto.yaml' "$validate"; then
        fail "scripts/validate.sh does not scan with the vendored ruleset."
    fi

    # The token has no business in the container any more: a vendored rule
    # set needs no registry login.
    if grep -q 'SEMGREP_APP_TOKEN' "$validate"; then
        fail "scripts/validate.sh still hands the Semgrep token to the scanner."
    fi

    # The vendored ruleset has to be the payload its header claims.
    if ! python3 - "$ruleset" <<'PY'
import hashlib
import re
import sys

path = sys.argv[1]
data = open(path, "rb").read()
lines = data.split(b"\n")
index = 0
while index < len(lines) and lines[index].startswith(b"#"):
    index += 1
payload = b"\n".join(lines[index:])
recorded = None
for line in lines[:index]:
    match = re.search(rb"sha256 of the payload below the header: ([0-9a-f]{64})", line)
    if match:
        recorded = match.group(1).decode()
if recorded is None:
    print("the vendored ruleset does not record its payload hash")
    sys.exit(1)
if hashlib.sha256(payload).hexdigest() != recorded:
    print("the vendored ruleset does not match the hash in its header")
    sys.exit(1)
if not payload.startswith(b"rules:"):
    print("the vendored ruleset does not hold a rule set")
    sys.exit(1)
PY
    then
        fail "the vendored ruleset does not match the hash in its header."
    fi
}

check_tree "$ROOT"

# Prove the check catches an unpinned scan, on a throwaway copy of the tree.
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT
mkdir -p "$workspace/scripts" "$workspace/semgrep"
cp "$ROOT/scripts/validate.sh" "$workspace/scripts/"
cp "$ROOT/semgrep/semgrep-auto.yaml" "$workspace/semgrep/"

# A mutable tag has to be caught.
sed -i.bak 's|semgrep/semgrep:[0-9.]*@sha256:[0-9a-f]*|semgrep/semgrep:latest|' "$workspace/scripts/validate.sh"
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the pinning check accepted a Semgrep image that is not pinned by digest'
fi
cp "$ROOT/scripts/validate.sh" "$workspace/scripts/validate.sh"

# The registry's current rules have to be caught.
# The literal text is what is matched here, so the shell must not expand it.
# shellcheck disable=SC2016
sed -i.bak 's|--config "\$SEMGREP_CONFIG"|--config=auto|' "$workspace/scripts/validate.sh"
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the pinning check accepted a scan with the registry rules'
fi
cp "$ROOT/scripts/validate.sh" "$workspace/scripts/validate.sh"

# A token handed to the scanner has to be caught.
# The literal text is what is matched here, so the shell must not expand it.
# shellcheck disable=SC2016
sed -i.bak 's|--config "\$SEMGREP_CONFIG"|--config "$SEMGREP_CONFIG" -e SEMGREP_APP_TOKEN|' "$workspace/scripts/validate.sh"
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the pinning check accepted a scan that hands the Semgrep token to the scanner'
fi
cp "$ROOT/scripts/validate.sh" "$workspace/scripts/validate.sh"

# A ruleset that no longer matches its recorded hash has to be caught.
printf '\n# tampered\n' >>"$workspace/semgrep/semgrep-auto.yaml"
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the pinning check accepted a vendored ruleset that does not match its header'
fi

printf 'PASS: the validation gate scans with a digest-pinned image and the vendored rule set\n'
