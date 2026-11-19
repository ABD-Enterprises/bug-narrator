#!/usr/bin/env bash
#
# Pins that the version bump script refuses to run on a dirty tree, and that
# it writes every file it changes by replacing the file rather than by
# truncating it in place.
#
# The bump rewrites four files that have to agree with each other. A bump
# over a tree that already carries changes mixes somebody else's work with
# the version change, and a failure part-way through leaves a half-bumped
# tree. Writing a file in place means a reader can see half of it.
#
# The test runs the real script against a throwaway tree, so it exercises the
# script itself and not a copy of its logic.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

# ── a throwaway tree with the files the bump touches ────────────────────────
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT

make_tree() {
    local tree="$1"
    mkdir -p "$tree/scripts"
    cp "$ROOT_DIR/scripts/bump_version.sh" "$tree/scripts/bump_version.sh"
    cp "$ROOT_DIR/scripts/check_version_consistency.sh" "$tree/scripts/check_version_consistency.sh"
    chmod +x "$tree/scripts/bump_version.sh" "$tree/scripts/check_version_consistency.sh"

    printf '1.1.0\n' >"$tree/VERSION"
    cat >"$tree/project.yml" <<'YAML'
name: BugNarrator
options:
  bundleIdPrefix: com.abdenterprises
settings:
  base:
    MARKETING_VERSION: 1.1.0
    CURRENT_PROJECT_VERSION: 47
YAML
    cat >"$tree/CHANGELOG.md" <<'MARKDOWN'
# Changelog

## Unreleased

- [FIX] Something that is not released yet.
MARKDOWN
    cat >"$tree/CHANGELOG-archive.md" <<'MARKDOWN'
# Changelog archive

## 1.1.0 - 2026-01-01

- The released version.
MARKDOWN

    git -C "$tree" init --quiet
    git -C "$tree" add --all
    git -C "$tree" \
        -c user.name='Version Bump Test' \
        -c user.email='bump@example.invalid' \
        commit --quiet -m 'the tree the bump runs against'
}

# ── 1. a clean tree is bumped ───────────────────────────────────────────────
clean="$workspace/clean"
make_tree "$clean"
if ! "$clean/scripts/bump_version.sh" 1.2.0 >"$workspace/clean.out" 2>&1; then
    cat "$workspace/clean.out" >&2
    fail 'the bump refused to run on a clean tree'
fi
if [[ "$(tr -d '[:space:]' <"$clean/VERSION")" != "1.2.0" ]]; then
    fail "the bump left VERSION at $(cat "$clean/VERSION")"
fi
if ! grep -q 'MARKETING_VERSION: 1.2.0' "$clean/project.yml"; then
    fail 'the bump did not update project.yml'
fi
if ! grep -q '## 1.2.0 -' "$clean/CHANGELOG-archive.md"; then
    fail 'the bump did not archive the released version'
fi

# ── 2. a dirty tree is refused, and nothing is written ─────────────────────
dirty="$workspace/dirty"
make_tree "$dirty"
printf 'a local edit that is not the version bump\n' >>"$dirty/VERSION"
before_version="$(cat "$dirty/VERSION")"
before_archive="$(cat "$dirty/CHANGELOG-archive.md")"
if "$dirty/scripts/bump_version.sh" 1.2.0 >"$workspace/dirty.out" 2>&1; then
    fail 'the bump ran on a tree with uncommitted changes'
fi
if ! grep -qi 'uncommitted changes' "$workspace/dirty.out"; then
    cat "$workspace/dirty.out" >&2
    fail 'the bump did not say that the tree has uncommitted changes'
fi
if [[ "$(cat "$dirty/VERSION")" != "$before_version" ]]; then
    fail 'the refused bump still wrote VERSION'
fi
if [[ "$(cat "$dirty/CHANGELOG-archive.md")" != "$before_archive" ]]; then
    fail 'the refused bump still wrote the changelog archive'
fi

# ── 3. every file the bump changes is replaced, not truncated in place ─────
# A file that is truncated and rewritten keeps its identity; a file that is
# written through a temporary file and renamed does not. That difference is
# what keeps a reader from seeing half a file.
inode_of() {
    python3 -c 'import os, sys; print(os.stat(sys.argv[1]).st_ino)' "$1"
}
replaced="$workspace/replaced"
make_tree "$replaced"
# Every file the bump changes, not one per implementation: the scope is all
# four.
before_inodes=()
for file in VERSION project.yml CHANGELOG.md CHANGELOG-archive.md; do
    before_inodes+=("$(inode_of "$replaced/$file")")
done
if ! "$replaced/scripts/bump_version.sh" 1.2.0 >"$workspace/replaced.out" 2>&1; then
    cat "$workspace/replaced.out" >&2
    fail 'the bump refused to run on a clean tree'
fi
index=0
for file in VERSION project.yml CHANGELOG.md CHANGELOG-archive.md; do
    if [[ "$(inode_of "$replaced/$file")" == "${before_inodes[$index]}" ]]; then
        fail "the bump rewrote $file in place instead of replacing it"
    fi
    index=$((index + 1))
done

# ── 3b. the mode of a replaced file is kept ────────────────────────────────
mode_tree="$workspace/mode"
make_tree "$mode_tree"
chmod 600 "$mode_tree/VERSION"
if ! "$mode_tree/scripts/bump_version.sh" 1.2.0 >"$workspace/mode.out" 2>&1; then
    cat "$workspace/mode.out" >&2
    fail 'the bump refused to run on a clean tree'
fi
mode="$(stat -c '%a' "$mode_tree/VERSION" 2>/dev/null || stat -f '%Lp' "$mode_tree/VERSION" 2>/dev/null || echo '')"
if [[ -n "$mode" && "$mode" != "600" ]]; then
    fail "the bump changed the mode of VERSION to $mode"
fi

# ── 4. the bump leaves no temporary files behind ───────────────────────────
leftovers="$(find "$replaced" -maxdepth 2 \( -name '*.tmp' -o -name '*.??????' \) -not -path '*/.git/*' || true)"
if [[ -n "$leftovers" ]]; then
    printf '%s\n' "$leftovers" >&2
    fail 'the bump left temporary files behind'
fi

printf 'PASS: the version bump refuses a dirty tree and replaces the files it writes\n'
