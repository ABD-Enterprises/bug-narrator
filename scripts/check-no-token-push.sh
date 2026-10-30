#!/usr/bin/env bash
#
# Keeps the job token out of the git configuration, and out of the repository.
#
# Every `actions/checkout` used the default `persist-credentials: true`, so the
# job's `GITHUB_TOKEN` stayed in `.git/config` for the rest of the job, next to
# whatever the job then ran - including pull request code in the same job. A
# later step that ran third-party code, or a script that read the git
# configuration, could pick it up.
#
# Turning the credential off is only half of it. The other half is that
# nothing pushes with the job's token: a workflow that pushed would have to
# put the credential back into the git configuration itself, and the push
# would be a write to the repository that nothing in this repository needs.
# The release workflows publish releases with `gh`, not with git, and they are
# behind the release environment gate.
#
# The check is not a search for the word "push". A command that mentions it -
# an echo, a note, a git configuration key - does not push, so only the
# commands of a `run:` block are looked at, and a comment is not a command.
#
# It proves itself: a checkout that keeps the credential, a checkout that
# never says what to do with it, and a workflow that pushes all have to be
# rejected, or the check would be decoration.
#
# It runs as part of scripts/validate.sh, so a workflow that starts keeping
# the token fails the push that introduced it rather than being noticed
# later.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

WORKFLOW_DIR="${1:-$ROOT/.github/workflows}"
SELF_TEST_WORK=""

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

# Prints one line per checkout that does not turn the credential off:
#   <file>: a checkout does not set persist-credentials: false
#   <file>: a checkout sets persist-credentials to <value>
#
# The value is read from the block that belongs to the checkout, not from the
# file: a `persist-credentials` key under some other step says nothing about
# the checkout, and a checkout without the key at all is the case that
# matters, because the default is to keep the credential.
find_unpinned_checkouts() {
    awk '
        function indent_of(line,   n) {
            n = 0
            while (substr(line, n + 1, 1) == " ") n++
            return n
        }
        function normalize(value) {
            sub(/^[ \t]+/, "", value)
            sub(/[ \t]+$/, "", value)
            if (value ~ /^".*"$/) { value = substr(value, 2, length(value) - 2) }
            else if (value ~ /^'"'"'.*'"'"'$/) { value = substr(value, 2, length(value) - 2) }
            return value
        }
        function close_checkout() {
            if (in_checkout && !pinned) {
                printf "%s: a checkout does not set persist-credentials: false\n", FILENAME
                problems = 1
            }
            in_checkout = 0; pinned = 0
        }
        {
            ind = indent_of($0)
            trimmed = substr($0, ind + 1)

            if (in_checkout) {
                # The step ends when the indentation drops back, or when the
                # next step begins at the same level.
                if (ind < checkout_indent || (ind == checkout_indent && trimmed ~ /^- /)) {
                    close_checkout()
                } else if (ind > checkout_indent && trimmed ~ /^persist-credentials:/) {
                    value = trimmed
                    sub(/^persist-credentials:[ \t]*/, "", value)
                    value = normalize(value)
                    sub(/[ \t]+#.*$/, "", value)
                    if (value != "false") {
                        printf "%s: a checkout sets persist-credentials to %s, expected false\n", FILENAME, value
                        problems = 1
                    }
                    pinned = 1
                }
            }

            if (trimmed ~ /^(- )?uses:[ \t]*actions\/checkout@/) {
                close_checkout()
                in_checkout = 1
                checkout_indent = ind
                pinned = 0
            }
        }
        END {
            close_checkout()
            exit problems
        }
    ' "$@"
}

# Prints one line per command that pushes with git:
#   <file>:<line>: <command>
#
# Only the commands of a `run:` block are read. A `run:` block is the part of
# the file that runs, and a line that mentions a push without running one - an
# echo, a note, a git configuration key - does not push.
find_git_pushes() {
    awk '
        function indent_of(line,   n) {
            n = 0
            while (substr(line, n + 1, 1) == " ") n++
            return n
        }
        function test_command(cmd,   n, words, i, j, segments, s, seg, m, k) {
            gsub(/["'"'"']/, "", cmd)
            gsub(/[[:space:]]+/, " ", cmd)
            sub(/^[ \t]+/, "", cmd)
            sub(/[ \t]+$/, "", cmd)
            if (cmd == "") return
            # A command that mentions a push without running one - an echo, a
            # note - does not push. The command that runs is the first word of
            # each segment of the pipeline, so "git" has to be that word and
            # not an argument to something else.
            m = split(cmd, segments, /[;|&]+/)
            for (s = 1; s <= m; s++) {
                seg = segments[s]
                gsub(/^[ \t]+/, "", seg)
                gsub(/[ \t]+$/, "", seg)
                if (seg == "") continue
                n = split(seg, words, " ")
                # A leading environment assignment is not the command.
                k = 1
                while (k <= n && words[k] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) k++
                if (k <= n && words[k] == "env") {
                    k++
                    while (k <= n && words[k] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) k++
                }
                if (k > n || words[k] != "git") continue
                # "git push", "git -c key=value push", "git --no-pager push".
                for (j = k + 1; j <= n && j <= k + 6; j++) {
                    if (words[j] == "push") {
                        printf "%s:%d: %s\n", FILENAME, FNR, cmd
                        problems = 1
                        return
                    }
                }
            }
        }
        function flush_run() {
            if (!inrun) return
            n = split(run_text, lines, "\n")
            for (i = 1; i <= n; i++) {
                line = lines[i]
                sub(/^[ \t]+/, "", line)
                if (line == "") continue
                # A comment is not a command.
                if (line ~ /^#/) continue
                sub(/[ \t]+#.*$/, "", line)
                test_command(line)
            }
            inrun = 0
            run_text = ""
        }
        {
            ind = indent_of($0)
            if (inrun) {
                if ($0 ~ /^[[:space:]]*$/ || ind > run_indent) {
                    run_text = run_text $0 "\n"
                    next
                }
                flush_run()
            }
            if ($0 ~ /^[ \t]*run:[ \t]*[|>]/) {
                inrun = 1
                run_indent = ind
                next
            }
        }
        END {
            flush_run()
            exit problems
        }
    ' "$@"
}

check_workflows() {
    local directory="$1"
    local files=()

    if [[ ! -d "$directory" ]]; then
        return 0
    fi

    while IFS= read -r file; do
        files+=("$file")
    done < <(find "$directory" -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)

    if [[ ${#files[@]} -eq 0 ]]; then
        return 0
    fi

    local unpinned pushes
    unpinned="$(find_unpinned_checkouts "${files[@]}")" && unpinned="" || true
    pushes="$(find_git_pushes "${files[@]}")" && pushes="" || true

    if [[ -n "$unpinned" ]]; then
        printf '%s\n' "$unpinned" >&2
        return 1
    fi

    if [[ -n "$pushes" ]]; then
        printf '%s\n' "$pushes" >&2
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------- self-test
#
# The check has to reject what it is there to reject, or it is decoration.
self_test() {
    # The trap is set on a global: a local would be gone by the time the
    # script exits, and the trap would fail on an unbound name.
    SELF_TEST_WORK="$(mktemp -d)"
    trap 'rm -rf "$SELF_TEST_WORK"' EXIT
    work="$SELF_TEST_WORK"

    mkdir -p "$work/good" "$work/keeps" "$work/missing" "$work/pushes"

    cat >"$work/good/ci.yml" <<'YAML'
name: good
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803
        with:
          persist-credentials: false
      - name: A step that mentions a push without running one
        run: |
          echo "we do not git push here"
          git config --get push.default || true
YAML

    cat >"$work/keeps/ci.yml" <<'YAML'
name: keeps
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803
        with:
          persist-credentials: true
YAML

    cat >"$work/missing/ci.yml" <<'YAML'
name: missing
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803
        with:
          fetch-depth: 2
YAML

    cat >"$work/pushes/ci.yml" <<'YAML'
name: pushes
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803
        with:
          persist-credentials: false
      - name: Push with git
        run: |
          git push origin main
YAML

    # The fixtures are expected to be rejected, so what the check says about
    # them is not part of the output.
    check_workflows "$work/good" 2>/dev/null || fail "the check rejected a workflow that is correct"
    if check_workflows "$work/keeps" 2>/dev/null; then
        fail "the check accepted a checkout that keeps the credential"
    fi
    if check_workflows "$work/missing" 2>/dev/null; then
        fail "the check accepted a checkout that says nothing about the credential"
    fi
    if check_workflows "$work/pushes" 2>/dev/null; then
        fail "the check accepted a workflow that pushes with git"
    fi
}

self_test

if ! check_workflows "$WORKFLOW_DIR"; then
    fail "a workflow keeps the job token in the git configuration, or pushes with git"
fi

printf 'PASS: no workflow keeps the job token in the git configuration, and none pushes with git\n'
