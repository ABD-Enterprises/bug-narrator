#!/usr/bin/env bash
#
# Pins that the fast Swift parse gate parses the test sources as well as the
# product sources.
#
# The gate is the fast feedback loop: a syntax error in a test file has to
# fail it, not only the full build, which is slower and runs in CI. The gate
# collected the Swift files under Sources/ only, so a syntax error in a test
# file passed the local gate.
#
# The test runs the real gate against a throwaway tree, with a stub toolchain
# that records the files it was handed. The stub is what makes the check
# possible without a Swift toolchain: the gate hands the toolchain the file
# list, and the list is what the test reads.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT

# ── a throwaway tree with the gate and one Swift file under each directory ──
make_tree() {
    local tree="$1"
    mkdir -p "$tree/scripts" "$tree/Sources/BugNarrator" "$tree/Tests/BugNarratorTests"
    cp "$ROOT_DIR/scripts/swift-parse-check.sh" "$tree/scripts/swift-parse-check.sh"
    chmod +x "$tree/scripts/swift-parse-check.sh"
    printf 'let product = 1\n' >"$tree/Sources/BugNarrator/Product.swift"
    printf 'let test = 2\n' >"$tree/Tests/BugNarratorTests/ProductTests.swift"
}

# A stub toolchain that records the files it was handed. The gate looks for
# swiftc on PATH, so the stub stands in for the toolchain. It fails on a file
# it cannot parse, the way the real toolchain does.
make_stub() {
    local stub_dir="$1"
    mkdir -p "$stub_dir"
    cat >"$stub_dir/swiftc" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$SWIFT_STUB_RECORD"
for argument in "$@"; do
  if [[ "$argument" == *Broken.swift ]]; then
    exit 1
  fi
done
exit 0
STUB
    chmod +x "$stub_dir/swiftc"
}

# A PATH with no toolchain in it, built rather than assumed: a directory that
# holds the tools the gate needs and nothing that answers to swiftc or swift.
# A hard-coded PATH would not do — on macOS the Xcode command line tools put
# swiftc in /usr/bin, so a path that names /usr/bin is not a path without a
# toolchain in it.
make_tool_free_path() {
    local stub_dir="$1"
    mkdir -p "$stub_dir"
    local tool resolved
    for tool in bash dirname mkdir rm find cat; do
        resolved="$(command -v "$tool" || true)"
        if [[ -n "$resolved" ]]; then
            ln -sf "$resolved" "$stub_dir/$tool"
        fi
    done
}

# ── 1. the gate parses the sources and the tests ───────────────────────────
tree="$workspace/tree"
make_tree "$tree"
make_stub "$workspace/stub"
record="$workspace/recorded.txt"

if ! SWIFT_STUB_RECORD="$record" PATH="$workspace/stub:$PATH" \
    "$tree/scripts/swift-parse-check.sh" >"$workspace/gate.out" 2>&1; then
    cat "$workspace/gate.out" >&2
    fail 'the parse gate failed on a tree with a stub toolchain'
fi

if [[ ! -s "$record" ]]; then
    fail 'the parse gate did not hand any file to the toolchain'
fi
if ! grep -q 'Sources/BugNarrator/Product.swift' "$record"; then
    fail 'the parse gate did not parse the product sources'
fi
if ! grep -q 'Tests/BugNarratorTests/ProductTests.swift' "$record"; then
    fail 'the parse gate did not parse the test sources'
fi

# ── 2. the gate still skips cleanly with no toolchain ──────────────────────
# The gate has to stay a clean skip where there is no Swift toolchain, or it
# would fail every checkout that has none.
skip_tree="$workspace/skip"
make_tree "$skip_tree"
tool_free="$workspace/tool-free"
make_tool_free_path "$tool_free"
if ! PATH="$tool_free" "$skip_tree/scripts/swift-parse-check.sh" >"$workspace/skip.out" 2>&1; then
    cat "$workspace/skip.out" >&2
    fail 'the parse gate failed instead of skipping when there was no toolchain'
fi
if ! grep -q 'NOT RUN: swift toolchain unavailable' "$skip_tree/artifacts/validation/swift-parse-status.txt"; then
    fail 'the parse gate did not say that it skipped for want of a toolchain'
fi

# ── 3. the gate still works in a tree that has only one of the two ─────────
# A checkout that carries the product sources but no test sources is still a
# checkout the gate has to run in.
sources_only="$workspace/sources-only"
mkdir -p "$sources_only/scripts" "$sources_only/Sources/BugNarrator"
cp "$ROOT_DIR/scripts/swift-parse-check.sh" "$sources_only/scripts/swift-parse-check.sh"
chmod +x "$sources_only/scripts/swift-parse-check.sh"
printf 'let product = 1\n' >"$sources_only/Sources/BugNarrator/Product.swift"
record="$workspace/recorded-sources.txt"
if ! SWIFT_STUB_RECORD="$record" PATH="$workspace/stub:$PATH" \
    "$sources_only/scripts/swift-parse-check.sh" >"$workspace/sources.out" 2>&1; then
    cat "$workspace/sources.out" >&2
    fail 'the parse gate failed in a tree that has no test sources'
fi
if ! grep -q 'Sources/BugNarrator/Product.swift' "$record"; then
    fail 'the parse gate did not parse the product sources in a tree without tests'
fi

# ── 4. a toolchain that reports a syntax error fails the gate ─────────────
# The stub fails on a file it cannot parse, the way the real toolchain does,
# so the gate has to fail with it.
broken_tree="$workspace/broken"
make_tree "$broken_tree"
printf 'let broken =\n' >"$broken_tree/Tests/BugNarratorTests/Broken.swift"
record="$workspace/recorded-broken.txt"
if SWIFT_STUB_RECORD="$record" PATH="$workspace/stub:$PATH" \
    "$broken_tree/scripts/swift-parse-check.sh" >"$workspace/broken.out" 2>&1; then
    fail 'the parse gate passed although the toolchain reported a syntax error'
fi
if ! grep -q 'FAIL: swift parse reported errors' "$broken_tree/artifacts/validation/swift-parse-status.txt"; then
    fail 'the parse gate did not say that the parse reported errors'
fi

printf 'PASS: the Swift parse gate parses the test sources as well as the product sources\n'
