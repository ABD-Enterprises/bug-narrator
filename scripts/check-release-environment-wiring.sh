#!/usr/bin/env bash
#
# Keeps the release environment gate and the release job's environment in step.
#
# scripts/check-release-environment.sh has no default environment name: the
# caller names the environment it deploys to, so a renamed environment cannot
# be checked under the old name while the job publishes into an environment
# with no protection rules at all. That only holds while the name the caller
# passes and the `environment:` key of the release job are the same
# environment, so this check compares them job by job for every workflow that
# runs the check.
#
# The comparison is per job on purpose. A file-level comparison would pass
# while the job that publishes the release had lost its `environment:` key and
# some other job in the same file still had one — which is exactly the
# ungated release the gate exists to prevent.
#
# It also pins that the gate runs *before* the release is published, and that
# it runs as a command: a comment that mentions the script is not a run of it,
# and a gate that runs after the release cannot retract the release.
#
# It proves itself: a drifted name, a step that stopped running the gate, a
# gate that runs too late and a check script with a baked-in name all have to
# be rejected, or the check would be decoration.
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

# Prints one record per job of a workflow file:
#   job|environment values|publishes|publish step|runs the gate|gate step|checked names
#
# The environment values and the checked names are space separated lists. The
# two step numbers are the index of the step that publishes the release and
# the index of the step that runs the gate; 0 means "not in this job".
#
# Only a step's run command counts. A line that mentions the script in a
# comment does not run it, and the order of the steps matters: the gate has to
# run before the release exists.
parse_jobs() {
    local file="$1"

    awk '
        function flush() {
            if (job != "") {
                printf "%s|%s|%d|%d|%d|%d|%s\n", job, envs, publishes, publish_step, gate, gate_step, gate_envs
            }
            job = ""; envs = ""; publishes = 0; publish_step = 0; gate = 0; gate_step = 0; gate_envs = ""; step = 0
        }
        # A command counts only when it runs the thing. A comment that names
        # the script does not run it, and a command that merely mentions it
        # (an echo, a note) does not run it either.
        function note_run(text) {
            cmd = text
            sub(/^[[:space:]]*/, "", cmd)
            if (cmd ~ /^#/) { return }
            sub(/^(bash|sh|exec)[[:space:]]+/, "", cmd)
            # The first one is the one that matters: the gate has to run
            # before the release exists, and the release is published by the
            # first step that creates it.
            if (gate_step == 0 && cmd ~ /^(\.\/)?scripts\/check-release-environment\.sh([[:space:]]|$)/) {
                gate = 1; gate_step = step
            }
            if (publish_step == 0 && (cmd ~ /"?release"?[[:space:],]+"?create/ || cmd ~ /"?release"?[[:space:],]+"?upload/)) {
                publishes = 1; publish_step = step
            }
        }
        /^jobs:[ \t]*$/ { injobs = 1; next }
        injobs && /^[^ \t]/ { flush(); injobs = 0; next }
        injobs && /^  [A-Za-z0-9_.-]+:[ \t]*$/ { flush(); job = $1; sub(/:$/, "", job); next }
        injobs && job != "" {
            if ($0 ~ /^      - /) { step++ }

            # A job-level environment: key sits at the job level indentation.
            if ($0 ~ /^    environment:[ \t]*[A-Za-z0-9._-]+/) {
                value = $0; sub(/^    environment:[ \t]*/, "", value)
                envs = (envs == "" ? value : envs " " value)
            }
            if ($0 ~ /RELEASE_ENVIRONMENT:[ \t]*[A-Za-z0-9._-]+/) {
                value = $0; sub(/.*RELEASE_ENVIRONMENT:[ \t]*/, "", value)
                gate_envs = (gate_envs == "" ? value : gate_envs " " value)
            }

            # A step'"'"'s run command, on one line or as a block.
            if ($0 ~ /^[[:space:]]*run:[ \t]*/) {
                inrun = 1
                runindent = index($0, "run:") - 1
                rest = $0; sub(/^[[:space:]]*run:[ \t]*/, "", rest)
                note_run(rest)
                next
            }
            if (inrun) {
                if ($0 ~ /^[[:space:]]*$/) { next }
                indent = match($0, /[^ \t]/) - 1
                if (indent > runindent) {
                    note_run($0)
                    next
                }
                inrun = 0
            }
        }
        END { flush() }
    ' "$file"
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

        local checked
        if ! checked="$(read_values "$workflow" RELEASE_ENVIRONMENT)"; then
            fail "could not read the RELEASE_ENVIRONMENT values from $workflow."
        fi
        if [[ -z "$checked" ]]; then
            fail "$workflow runs $CHECK_SCRIPT_NAME without naming the environment (RELEASE_ENVIRONMENT)."
        fi
        if [[ "$(printf '%s\n' "$checked" | wc -l | tr -d ' ')" != "1" ]]; then
            fail "$workflow names more than one environment for the release gate: $checked"
        fi
        local gate_env="$checked"

        local jobs=""
        if ! jobs="$(parse_jobs "$workflow")"; then
            fail "could not read the jobs of $workflow."
        fi

        local publishing=0
        local job envs publishes publish_step gate gate_step gate_envs
        while IFS='|' read -r job envs publishes publish_step gate gate_step gate_envs; do
            [[ -n "$job" ]] || continue

            # A job that names an environment has to name the gate's.
            if [[ -n "$envs" && "$envs" != "$gate_env" ]]; then
                fail "$workflow: job \"$job\" deploys to \"$envs\", not the checked environment \"$gate_env\"."
            fi

            # A job that runs the gate has to name the environment it checks.
            if [[ "$gate" == "1" && " $gate_envs " != *" $gate_env "* ]]; then
                fail "$workflow: job \"$job\" runs the environment gate without checking \"$gate_env\"."
            fi

            if [[ "$publishes" != "1" ]]; then
                continue
            fi
            publishing=1

            # The job that publishes is the one that has to be gated. Without
            # its own environment key the release would publish with no
            # approval, whatever another job in the same file declares.
            if [[ -z "$envs" ]]; then
                fail "$workflow: job \"$job\" publishes a release but declares no environment."
            fi
            if [[ "$gate" != "1" ]]; then
                fail "$workflow: job \"$job\" publishes a release without running the environment gate."
            fi

            # The gate has to run before the release exists: a gate that runs
            # afterwards cannot retract what it should have stopped.
            if [[ "$gate_step" -ge "$publish_step" ]]; then
                fail "$workflow: job \"$job\" publishes a release in step $publish_step, before the gate runs in step $gate_step."
            fi
        done <<<"$jobs"

        if [[ "$publishing" == "0" ]]; then
            fail "$workflow runs $CHECK_SCRIPT_NAME but no job publishes a release to compare against."
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

restore_workflow() {
    cp "$ROOT/$1" "$workspace/$1"
}

# Applies a named mutation to a copy of a workflow. The mutations find the
# gate step by what it runs rather than by the exact wording of the step, so
# they keep proving what they are meant to prove when the workflow's shape
# changes.
mutate_workflow() {
    local file="$1"
    local mutation="$2"

    python3 - "$file" "$mutation" <<'PYTHON'
import re
import sys

path, mutation = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()


def run_content(step):
    """The commands a step runs: the run line, or the lines of a run block."""
    commands = []
    in_block = False
    indent = 0
    for line in step.split("\n"):
        if not in_block:
            match = re.match(r"^(\s+)run:\s*(.*)$", line)
            if not match:
                continue
            indent = len(match.group(1))
            rest = match.group(2).strip()
            if rest and not rest.startswith("|"):
                commands.append(rest)
            elif rest.startswith("|"):
                in_block = True
            continue
        stripped = line.strip()
        if not stripped:
            continue
        if len(line) - len(line.lstrip()) <= indent:
            in_block = False
            continue
        if stripped.startswith("#"):
            continue
        commands.append(stripped)
    return commands


def publishes(step):
    return any(re.search(r"release\"?[\s,]+\"?(create|upload)", command) for command in run_content(step))


head, marker, rest = text.partition("\njobs:\n")
if not marker:
    print("the workflow has no jobs section")
    sys.exit(1)
jobs = re.split(r"(?m)^(?=  [A-Za-z0-9_.-]+:[ \t]*$)", "jobs:\n" + rest)

# The job that matters is the one that publishes the release.
target = None
for job_index, job in enumerate(jobs):
    steps = re.split(r"(?m)^(?=      - )", job)
    if any(publishes(step) for step in steps):
        target = (job_index, steps)
        break
if target is None:
    print("could not find the publishing job")
    sys.exit(1)
job_index, steps = target

gate_index = None
for index, step in enumerate(steps):
    if any("check-release-environment.sh" in command for command in run_content(step)):
        gate_index = index
        break
if gate_index is None:
    print("could not find the gate step")
    sys.exit(1)

if mutation == "mention" or mutation == "comment":
    # Replace the command that invokes the script, wherever it sits: the run
    # line of a step or a line inside a run block.
    replaced = False
    lines = steps[gate_index].split("\n")
    for line_index, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("#") or "check-release-environment.sh" not in stripped:
            continue
        indent = line[: len(line) - len(line.lstrip())]
        if stripped.startswith("run:"):
            prefix = indent + "run: "
        else:
            prefix = indent
        if mutation == "mention":
            lines[line_index] = prefix + 'echo "see scripts/check-release-environment.sh"'
        else:
            lines[line_index] = indent + "# bash scripts/check-release-environment.sh"
        replaced = True
        break
    if not replaced:
        print("could not replace the gate command")
        sys.exit(1)
    steps[gate_index] = "\n".join(lines)
elif mutation == "publish-before":
    early = '      - name: Publish GitHub Release\n        shell: bash\n        run: gh release create "$RELEASE_TAG"\n'
    steps.insert(gate_index, early)
elif mutation == "move-after-publish":
    publish_index = next(index for index, step in enumerate(steps) if publishes(step))
    gate = steps.pop(gate_index)
    steps.insert(publish_index + 1, gate)
else:
    print("unknown mutation")
    sys.exit(1)

jobs[job_index] = "".join(steps)
open(path, "w", encoding="utf-8").write(head + "\njobs:\n" + "".join(jobs))
PYTHON
}

# Applies a self-test mutation and fails when it changed nothing: a mutation
# that no longer matches the workflow's shape would otherwise look like a
# check that accepted a broken tree.
mutate() {
    local file="$1"
    shift
    local before
    before="$(cat "$file")"
    sed -i.bak "$@" "$file"
    if [[ "$before" == "$(cat "$file")" ]]; then
        fail "the self-test could not apply its mutation to $file; the workflow's shape changed"
    fi
}

# A name that no longer matches the job's environment has to be caught.
sed -i.bak 's/RELEASE_ENVIRONMENT: windows-release/RELEASE_ENVIRONMENT: windows-release-old/' \
    "$workspace/.github/workflows/windows-tester-release.yml"
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check accepted a release environment name that does not match the job environment'
fi
restore_workflow ".github/workflows/windows-tester-release.yml"

# A workflow that runs the check without naming the environment has to be caught.
sed -i.bak '/RELEASE_ENVIRONMENT: windows-release/d' \
    "$workspace/.github/workflows/local-transcription-windows.yml"
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check accepted a release workflow that does not name the environment'
fi
restore_workflow ".github/workflows/local-transcription-windows.yml"

# A release workflow that stopped running the gate has to be caught.
sed -i.bak '/check-release-environment.sh/d' \
    "$workspace/.github/workflows/local-transcription-windows.yml"
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check accepted a release workflow that does not run the environment gate'
fi
restore_workflow ".github/workflows/local-transcription-windows.yml"

# The publishing job losing its environment has to be caught, even when another
# job in the same file still declares one.
sed -i.bak '/^    environment: windows-release$/d' \
    "$workspace/.github/workflows/windows-tester-release.yml"
printf '\n  decoy-job:\n    runs-on: ubuntu-latest\n    environment: windows-release\n    steps:\n      - run: echo hi\n' \
    >>"$workspace/.github/workflows/windows-tester-release.yml"
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check accepted a publishing job without an environment'
fi
restore_workflow ".github/workflows/windows-tester-release.yml"

# A publishing job that deploys to another environment has to be caught.
sed -i.bak 's/^    environment: windows-release$/    environment: windows-release-other/' \
    "$workspace/.github/workflows/local-transcription-windows.yml"
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check accepted a publishing job that deploys to another environment'
fi
restore_workflow ".github/workflows/local-transcription-windows.yml"

# A publishing job that runs the gate without naming the environment has to be
# caught.
sed -i.bak '/RELEASE_ENVIRONMENT: windows-release/d' \
    "$workspace/.github/workflows/windows-tester-release.yml"
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check accepted a publishing job that does not name the environment'
fi
restore_workflow ".github/workflows/windows-tester-release.yml"

# A gate step that only mentions the script in a command that does not run it
# has to be caught.
mutate_workflow "$workspace/.github/workflows/windows-tester-release.yml" mention
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check accepted a gate step that does not run the gate'
fi
restore_workflow ".github/workflows/windows-tester-release.yml"

# A gate step that is only a comment has to be caught.
mutate_workflow "$workspace/.github/workflows/windows-tester-release.yml" comment
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check accepted a gate step that is only a comment'
fi
restore_workflow ".github/workflows/windows-tester-release.yml"

# A release published before the gate runs has to be caught.
mutate_workflow "$workspace/.github/workflows/windows-tester-release.yml" publish-before
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check accepted a release published before the gate runs'
fi
restore_workflow ".github/workflows/windows-tester-release.yml"

# The gate moved after the release it should have stopped has to be caught.
mutate_workflow "$workspace/.github/workflows/windows-tester-release.yml" move-after-publish
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check accepted a gate that runs after the release'
fi
restore_workflow ".github/workflows/windows-tester-release.yml"

# A baked-in environment name in the check script has to be caught.
printf '\n# windows-release\n' >>"$workspace/$CHECK_SCRIPT_NAME"
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check accepted a check script that names an environment itself'
fi

printf 'PASS: the release environment gate checks the same environment the release job deploys to\n'
