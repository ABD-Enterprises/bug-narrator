#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRASH_ROOT="${TRASH_ROOT:-$HOME/.Trash}"
TIMESTAMP="$(date +%s)"
TRASH_DIR="$TRASH_ROOT/bugnarrator-local-builds-$TIMESTAMP"

shopt -s nullglob

declare -a candidates=(
    "$ROOT_DIR/build/DerivedData/Build/Products/Release/BugNarrator.app"
)

for path in "$HOME"/Library/Developer/Xcode/DerivedData/*/Build/Products/Debug/BugNarrator.app; do
    candidates+=("$path")
done

for path in "$HOME"/Library/Developer/Xcode/DerivedData/*/Build/Products/Release/BugNarrator.app; do
    candidates+=("$path")
done

move_candidate() {
    local source_path="$1"
    local label="$2"
    local destination_path="$TRASH_DIR/$label.app"
    local suffix=2

    while [[ -e "$destination_path" ]]; do
        destination_path="$TRASH_DIR/$label-$suffix.app"
        suffix=$((suffix + 1))
    done

    mv "$source_path" "$destination_path"
    printf 'Moved %s -> %s\n' "$source_path" "$destination_path"
}

if [[ ! -d "$TRASH_ROOT" ]]; then
    mkdir -p "$TRASH_ROOT"
fi

mkdir -p "$TRASH_DIR"

moved_count=0
for candidate in "${candidates[@]}"; do
    [[ -e "$candidate" ]] || continue

    if [[ "$candidate" == "$ROOT_DIR"/build/* ]]; then
        move_candidate "$candidate" "BugNarrator-RepoRelease"
    else
        build_configuration="$(basename "$(dirname "$candidate")")"
        move_candidate "$candidate" "BugNarrator-$build_configuration"
    fi
    moved_count=$((moved_count + 1))
done

if [[ "$moved_count" -eq 0 ]]; then
    rmdir "$TRASH_DIR" 2>/dev/null || true
    echo "No local BugNarrator build app bundles were found."
    exit 0
fi

printf 'Moved %d local BugNarrator build bundle(s) into %s\n' "$moved_count" "$TRASH_DIR"
