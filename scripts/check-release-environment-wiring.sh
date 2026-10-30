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
# The environment the gate checks is taken from the gate step itself. A job
# level `env:` applies to every step, but a step level `env:` wins over it,
# so a decoy step elsewhere in the job must not be able to satisfy the check
# for a gate step that checks something else.
#
# It also pins that the gate runs *before* the release is published, that it
# runs as a command (a comment that mentions the script is not a run of it),
# that the command is the gate and nothing else (a step that swallows the
# gate's exit status would stay green when the gate fails), and that the step
# can fail the job at all (continue-on-error or a condition would let the
# release publish after the gate said no).
#
# It proves itself: a drifted name, a step that stopped running the gate, a
# gate that runs too late, a gate that cannot fail the job and a check script
# with a baked-in name all have to be rejected, or the check would be
# decoration. A publishing job that is not recognised as one — because it
# publishes with `gh release edit`, with a line continued command, or with a
# path split across quotes — has to be rejected too, or the guarantee would
# only hold for the commands it happens to know.
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
#   job|environment values|job environment values|publishes|publish step|runs
#   the gate|gate step|checked names|cannot fail
#
# The environment values and the checked names are space separated lists. The
# three step numbers are the index of the step that publishes the release, the
# index of the step that runs the gate and the index of the first step that
# was judged to publish; 0 means "not in this job". The last field says the
# gate step could not fail the job.
parse_jobs() {
    local file="$1"

    awk '
        function flush() {
            if (job != "") {
                printf "%s|%s|%d|%d|%d|%d|%s|%d\n", job, envs, publishes, publish_step, gate, gate_step, gate_envs, neutered
            }
            job = ""; envs = ""; job_envs = ""; publishes = 0; publish_step = 0; gate = 0; gate_step = 0; gate_envs = ""; neutered = 0
            pending_environment = 0
        }
        # A command counts only when it runs the thing. A comment that names
        # the script does not run it, and a command that merely mentions it
        # (an echo, a note) does not run it either.
        function test_command(cmd,   c) {
            sub(/^(bash|sh|exec)[[:space:]]+/, "", cmd)
            c = cmd
            # Quotes are dropped so a path that is split across quotes is
            # still one path, and whitespace is collapsed so a command that
            # is split across lines is still one command.
            gsub(/["'"'"']/, "", c)
            gsub(/[[:space:]]+/, " ", c)
            # The command has to be the gate and nothing else. A command that
            # swallows the exit status of the gate — "|| true", "; true", a
            # trailing "&" — would leave the step green when the gate fails,
            # which is the one thing the gate exists to prevent.
            if (c ~ /^(\.\/)?scripts\/check-release-environment\.sh$/) {
                step_gate = 1
            }
            # The release is published by creating it, by replacing its
            # assets, or by editing a draft into a published release — and by
            # the API behind those commands.
            if (c ~ /(^|[^A-Za-z0-9_])release (create|upload|edit|publish)/) {
                step_publish = 1
            }
            if (c ~ /\/releases/) {
                step_publish = 1
            }
        }
        # The commands of a run block. A command that is continued on the
        # next line is joined with it, so a release published by a line
        # continued command is still recognised as one.
        function classify(text,   n, i, line, cmd, pending, cont, parts) {
            n = split(text, parts, "\n")
            cmd = ""
            pending = 0
            for (i = 1; i <= n; i++) {
                line = parts[i]
                sub(/^[ \t]+/, "", line)
                if (line == "") { continue }
                if (line ~ /^#/) { continue }
                cont = (line ~ /\\$/)
                sub(/\\$/, "", line)
                if (cmd == "") {
                    cmd = line
                } else if (pending) {
                    cmd = cmd " " line
                } else {
                    test_command(cmd)
                    cmd = line
                }
                pending = cont
            }
            if (cmd != "") { test_command(cmd) }
        }
        function flush_run() {
            if (inrun) {
                classify(run_text)
            }
            inrun = 0
            run_text = ""
        }
        # A step is judged when it ends: its attributes can sit before or
        # after its run command.
        function close_step() {
            flush_run()
            if (step_gate) {
                if (step_conditional || (step_continue != "" && step_continue != "false")) {
                    neutered = 1
                }
                if (gate == 0) {
                    gate = 1
                    gate_step = step
                    # The environment the gate checks is the one the gate
                    # step itself sees: its own env, or the job env when the
                    # step does not set one. A step level env wins over the
                    # job level one, so a decoy step elsewhere in the job
                    # cannot stand in for the gate step.
                    gate_envs = (step_envs != "" ? step_envs : job_envs)
                }
            }
            if (step_publish && publish_step == 0) { publishes = 1; publish_step = step }
            step_continue = ""; step_conditional = 0; step_gate = 0; step_publish = 0; step_envs = ""
        }
        /^jobs:[ \t]*$/ { injobs = 1; next }
        injobs && /^[^ \t]/ { close_step(); flush(); injobs = 0; next }
        injobs && /^  [A-Za-z0-9_.-]+:[ \t]*$/ { close_step(); flush(); job = $1; sub(/:$/, "", job); step = 0; next }
        injobs && job != "" {
            if ($0 ~ /^      - /) { close_step(); step++ }

            # The attributes of the step: a gate that cannot fail the job is
            # not a gate.
            if ($0 ~ /^        continue-on-error:[ \t]*/) {
                value = $0; sub(/^        continue-on-error:[ \t]*/, "", value)
                # The value may be quoted; "false" means the same as false.
                gsub(/["'"'"']/, "", value)
                step_continue = value
            }
            if ($0 ~ /^        if:[ \t]*/) { step_conditional = 1 }

            # A job-level environment: key sits at the job level indentation.
            # It is either the scalar form or the object form, where the name
            # is on the next line.
            if ($0 ~ /^    environment:[ \t]*[A-Za-z0-9._-]+/) {
                value = $0; sub(/^    environment:[ \t]*/, "", value)
                envs = (envs == "" ? value : envs " " value)
                pending_environment = 0
            } else if ($0 ~ /^    environment:[ \t]*$/) {
                pending_environment = 1
            } else if (pending_environment && $0 ~ /^      name:[ \t]*[A-Za-z0-9._-]+/) {
                value = $0; sub(/^      name:[ \t]*/, "", value)
                envs = (envs == "" ? value : envs " " value)
                pending_environment = 0
            }

            # The environment the gate checks: a real setting, not a comment
            # that mentions one. The job level env applies to every step; a
            # step level env applies to that step alone and wins over it.
            if ($0 !~ /^[[:space:]]*#/ && $0 ~ /RELEASE_ENVIRONMENT:[ \t]*/) {
                value = $0
                sub(/.*RELEASE_ENVIRONMENT:[ \t]*/, "", value)
                sub(/[ \t]*#.*$/, "", value)
                sub(/[ \t]+$/, "", value)
                if ($0 ~ /^      RELEASE_ENVIRONMENT:/) {
                    if (job_envs == "") { job_envs = value }
                } else {
                    if (step_envs == "") { step_envs = value }
                }
            }

            # A step'"'"'s run command, on one line or as a block.
            if ($0 ~ /^[[:space:]]*run:[ \t]*/) {
                inrun = 1
                runindent = index($0, "run:") - 1
                rest = $0; sub(/^[[:space:]]*run:[ \t]*/, "", rest)
                run_text = rest
                next
            }
            if (inrun) {
                if ($0 ~ /^[[:space:]]*$/) { next }
                indent = match($0, /[^ \t]/) - 1
                if (indent > runindent) {
                    run_text = run_text "\n" $0
                    next
                }
                inrun = 0
            }
        }
        END { close_step(); flush() }
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
    # way, including any workflow added later. Only the workflow files
    # themselves are listed: the copies this script makes of them while it
    # proves itself are not workflows of the repository.
    local workflows=""
    if ! workflows="$(grep -rlF --include='*.yml' --include='*.yaml' -- "$CHECK_SCRIPT_NAME" "$workflow_dir" 2>&1)"; then
        if [[ -n "$workflows" ]]; then
            fail "could not list the workflows that run $CHECK_SCRIPT_NAME: $workflows"
        fi
        workflows=""
    fi
    if [[ -z "$workflows" ]]; then
        fail "no workflow runs $CHECK_SCRIPT_NAME; the release environment gate would never run."
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
        local preflights=0
        local job envs publishes publish_step gate gate_step gate_envs neutered
        while IFS='|' read -r job envs publishes publish_step gate gate_step gate_envs neutered; do
            [[ -n "$job" ]] || continue

            # A job that names an environment has to name the gate's.
            if [[ -n "$envs" && "$envs" != "$gate_env" ]]; then
                fail "$workflow: job \"$job\" deploys to \"$envs\", not the checked environment \"$gate_env\"."
            fi

            # A job that runs the gate has to name the environment it checks.
            if [[ "$gate" == "1" && "$gate_envs" != "$gate_env" ]]; then
                fail "$workflow: job \"$job\" runs the environment gate without checking \"$gate_env\"."
            fi

            # A gate that cannot fail the job is not a gate.
            if [[ "$neutered" == "1" ]]; then
                fail "$workflow: job \"$job\" runs the environment gate in a step that cannot fail the job."
            fi

            if [[ "$gate" == "1" && -z "$envs" ]]; then
                preflights=$((preflights + 1))
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
            # after the release cannot retract what it should have stopped.
            if [[ "$gate_step" -ge "$publish_step" ]]; then
                fail "$workflow: job \"$job\" publishes a release in step $publish_step, before the gate runs in step $gate_step."
            fi
        done <<<"$jobs"

        if [[ "$publishing" == "0" ]]; then
            fail "$workflow runs $CHECK_SCRIPT_NAME but no job publishes a release to compare against."
        fi

        # The preflight runs the gate too, so a broken environment is caught
        # before a Windows runner is reserved. The preflight is the job that
        # runs the gate and declares no environment of its own.
        if [[ "$preflights" -lt 1 ]]; then
            fail "$workflow runs the environment gate only in the gated job; the preflight has to run it as well."
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
    pending = []
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
        # A command continued on the next line is one command.
        if stripped.endswith("\\"):
            pending.append(stripped[:-1].strip())
            continue
        if pending:
            pending.append(stripped)
            commands.append(" ".join(pending))
            pending = []
            continue
        commands.append(stripped)
    if pending:
        commands.append(" ".join(pending))
    return commands


def publishes(step):
    """Whether a step publishes a release.

    The release is created, replaced or edited into a published release, by
    the gh commands or by the API behind them. Quotes are dropped so a path
    split across quotes is still one path, and whitespace is collapsed so a
    command split across lines is still one command.
    """
    for command in run_content(step):
        collapsed = re.sub(r"[\"']", "", command)
        collapsed = re.sub(r"\s+", " ", collapsed)
        if re.search(r"(^|[^A-Za-z0-9_])release (create|upload|edit|publish)", collapsed):
            return True
        if "/releases" in collapsed:
            return True
    return False


head, marker, rest = text.partition("\njobs:\n")
if not marker:
    print("the workflow has no jobs section")
    sys.exit(1)
jobs = re.split(r"(?m)^(?=  [A-Za-z0-9_.-]+:[ \t]*$)", "jobs:\n" + rest)

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
    replaced = False
    lines = steps[gate_index].split("\n")
    for line_index, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("#") or "check-release-environment.sh" not in stripped:
            continue
        indent = line[: len(line) - len(line.lstrip())]
        prefix = indent + "run: " if stripped.startswith("run:") else indent
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
elif mutation == "continue-on-error":
    lines = steps[gate_index].split("\n")
    for line_index, line in enumerate(lines):
        if line.strip().startswith("run:"):
            lines.insert(line_index, "        continue-on-error: true")
            break
    steps[gate_index] = "\n".join(lines)
elif mutation == "quoted-continue-on-error":
    lines = steps[gate_index].split("\n")
    for line_index, line in enumerate(lines):
        if line.strip().startswith("run:"):
            lines.insert(line_index, '        continue-on-error: "false"')
            break
    steps[gate_index] = "\n".join(lines)
elif mutation == "conditional":
    lines = steps[gate_index].split("\n")
    for line_index, line in enumerate(lines):
        if line.strip().startswith("run:"):
            lines.insert(line_index, "        if: false")
            break
    steps[gate_index] = "\n".join(lines)
elif mutation == "decoy-env":
    lines = steps[gate_index].split("\n")
    replaced = False
    for line_index, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("#") or "RELEASE_ENVIRONMENT:" not in stripped:
            continue
        indent = line[: len(line) - len(line.lstrip())]
        lines[line_index] = indent + "RELEASE_ENVIRONMENT: ${{ vars.RELEASE_ENV }}"
        replaced = True
        break
    if not replaced:
        print("could not find the environment of the gate step")
        sys.exit(1)
    steps[gate_index] = "\n".join(lines)
    # A decoy step carries the name the gate is supposed to check, so the
    # file still names exactly one environment.
    decoy = (
        "      - name: Decoy\n"
        "        env:\n"
        "          RELEASE_ENVIRONMENT: windows-release\n"
        "        run: echo hi\n"
    )
    steps.insert(gate_index + 1, decoy)
elif mutation == "environment-object-form":
    job_text, count = re.subn(
        r"(?m)^(    )environment:([ \t]*)([A-Za-z0-9._-]+)[ \t]*$",
        r"\1environment:\n\1  name: \3",
        jobs[job_index],
    )
    if count != 1:
        print("could not rewrite the environment key")
        sys.exit(1)
    jobs[job_index] = job_text
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

# Appends a job that publishes a release without declaring an environment.
# The command is the only thing that differs between the cases, so the check
# has to recognise every one of them as a publishing job.
append_ungated_publisher() {
    local file="$1"
    local command="$2"
    {
        printf '\n  ungated-publisher:\n'
        printf '    runs-on: ubuntu-latest\n'
        printf '    permissions:\n'
        printf '      contents: write\n'
        printf '    steps:\n'
        printf '      - name: Publish\n'
        printf '        shell: bash\n'
        printf '        run: |\n'
        printf '          %s\n' "$command"
    } >>"$file"
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

# A gate step that cannot fail the job has to be caught.
mutate_workflow "$workspace/.github/workflows/windows-tester-release.yml" continue-on-error
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check accepted a gate step that cannot fail the job'
fi
restore_workflow ".github/workflows/windows-tester-release.yml"

# A gate step that does not always run has to be caught.
mutate_workflow "$workspace/.github/workflows/windows-tester-release.yml" conditional
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check accepted a conditional gate step'
fi
restore_workflow ".github/workflows/windows-tester-release.yml"

# A gate step that checks a different environment, while a decoy step in the
# same job carries the name the check is looking for, has to be caught.
mutate_workflow "$workspace/.github/workflows/windows-tester-release.yml" decoy-env
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check accepted a gate step that checks another environment'
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

# A publishing job that publishes a draft into a published release has to be
# caught: it is a publishing job without an environment. The commands are
# written as the shell would see them, so the dollar signs stay literal.
# shellcheck disable=SC2016
append_ungated_publisher "$workspace/.github/workflows/windows-tester-release.yml" \
    'gh release edit "$RELEASE_TAG" --draft=false'
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check accepted a publishing job that publishes with gh release edit'
fi
restore_workflow ".github/workflows/windows-tester-release.yml"

# A publishing job whose release command is continued on the next line has to
# be caught.
# shellcheck disable=SC2016
append_ungated_publisher "$workspace/.github/workflows/windows-tester-release.yml" \
    'gh release \
            create "$RELEASE_TAG"'
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check accepted a publishing job with a continued release command'
fi
restore_workflow ".github/workflows/windows-tester-release.yml"

# A publishing job whose release path is split across quotes has to be caught.
# shellcheck disable=SC2016
append_ungated_publisher "$workspace/.github/workflows/windows-tester-release.yml" \
    'gh api "repos/$GITHUB_REPOSITORY"/"releases" --method POST'
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check accepted a publishing job with a split release path'
fi
restore_workflow ".github/workflows/windows-tester-release.yml"

# The object form of the environment key is valid, so it has to be accepted.
mutate_workflow "$workspace/.github/workflows/windows-tester-release.yml" environment-object-form
if ! (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check rejected the object form of the environment key'
fi
restore_workflow ".github/workflows/windows-tester-release.yml"

# A quoted "false" is the same as false, so the gate step can still fail the
# job and the workflow has to be accepted.
mutate_workflow "$workspace/.github/workflows/windows-tester-release.yml" quoted-continue-on-error
if ! (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check rejected a quoted continue-on-error of false'
fi
restore_workflow ".github/workflows/windows-tester-release.yml"

# A baked-in environment name in the check script has to be caught.
printf '\n# windows-release\n' >>"$workspace/$CHECK_SCRIPT_NAME"
if (check_tree "$workspace") >/dev/null 2>&1; then
    fail 'the wiring check accepted a check script that names an environment itself'
fi

printf 'PASS: the release environment gate checks the same environment the release job deploys to\n'
