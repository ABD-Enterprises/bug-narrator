#!/usr/bin/env python3
"""Generate the session-bundle contract fixture from the product spec.

Usage:
  python3 scripts/sync_product_spec_contract.py
  python3 scripts/sync_product_spec_contract.py --check
"""

import argparse
import json
import pathlib
import re
import sys
from typing import Optional


REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = "docs/architecture/product-spec.md"
SOURCE_ANCHOR = f"{SOURCE}#session-bundle"
FIXTURE = "contract-fixtures/session-bundle-layout.json"
BUCKETS = ("always", "whenIssueExtractionHasRun")
BULLET = re.compile(r"^- `([^`]+)`(?:\s+.*)?$")


class ContractError(ValueError):
    """The marked product-spec contract is invalid."""


def marker(bucket: str, boundary: str) -> str:
    return f"<!-- {boundary} SESSION-BUNDLE-LAYOUT {bucket} -->"


def validate_relative_path(path: str, bucket: str) -> None:
    if path != path.strip() or not path:
        raise ContractError(f"empty or whitespace-padded path in {bucket}")
    if "\\" in path or path.startswith("/") or "//" in path:
        raise ContractError(f"path is not a normalized relative path in {bucket}: {path}")

    parts = path.removesuffix("/").split("/")
    if not all(parts) or any(part in {".", ".."} for part in parts):
        raise ContractError(f"path is not a normalized relative path in {bucket}: {path}")


def read_bucket(markdown: str, bucket: str) -> list[str]:
    begin = marker(bucket, "BEGIN")
    end = marker(bucket, "END")

    begin_count = markdown.count(begin)
    end_count = markdown.count(end)
    if begin_count != 1 or end_count != 1:
        raise ContractError(
            f"expected exactly one marker pair for {bucket}; "
            f"found {begin_count} BEGIN and {end_count} END markers"
        )

    begin_index = markdown.index(begin) + len(begin)
    end_index = markdown.index(end)
    if end_index <= begin_index:
        raise ContractError(f"END marker precedes BEGIN marker for {bucket}")

    paths: list[str] = []
    for line in markdown[begin_index:end_index].splitlines():
        if not line.strip():
            continue
        match = BULLET.fullmatch(line)
        if match is None:
            raise ContractError(f"malformed bullet in {bucket}: {line}")
        path = match.group(1)
        validate_relative_path(path, bucket)
        if path in paths:
            raise ContractError(f"duplicate path in {bucket}: {path}")
        paths.append(path)

    if not paths:
        raise ContractError(f"marked block has no paths: {bucket}")
    return sorted(paths)


def contract_from_spec() -> dict[str, object]:
    markdown = (REPO_ROOT / SOURCE).read_text(encoding="utf-8")
    contract: dict[str, object] = {"source": SOURCE_ANCHOR}
    for bucket in BUCKETS:
        contract[bucket] = read_bucket(markdown, bucket)

    overlap = set(contract["always"]) & set(contract["whenIssueExtractionHasRun"])
    if overlap:
        raise ContractError(f"paths appear in both buckets: {', '.join(sorted(overlap))}")
    return contract


def render(contract: dict[str, object]) -> bytes:
    return (json.dumps(contract, indent=2) + "\n").encode("utf-8")


def fixture_contract(current: bytes) -> Optional[dict[str, object]]:
    try:
        decoded = json.loads(current.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None
    return decoded if isinstance(decoded, dict) else None


def report_stale(expected: dict[str, object], current: bytes) -> None:
    print(f"FAIL: {FIXTURE} is stale relative to {SOURCE_ANCHOR}", file=sys.stderr)
    fixture = fixture_contract(current)
    if fixture is not None:
        for bucket in BUCKETS:
            fixture_paths = fixture.get(bucket)
            if fixture_paths != expected[bucket]:
                print(f"  {bucket}:", file=sys.stderr)
                print(f"    spec:    {json.dumps(expected[bucket])}", file=sys.stderr)
                print(f"    fixture: {json.dumps(fixture_paths)}", file=sys.stderr)
    print(f"Run python3 scripts/sync_product_spec_contract.py and commit the result.", file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if the fixture is stale")
    args = parser.parse_args()

    try:
        contract = contract_from_spec()
    except (ContractError, OSError) as error:
        print(f"FAIL: invalid session-bundle contract: {error}", file=sys.stderr)
        return 1

    expected = render(contract)
    fixture_path = REPO_ROOT / FIXTURE
    current = fixture_path.read_bytes() if fixture_path.exists() else b""

    if args.check:
        if current != expected:
            report_stale(contract, current)
            return 1
        print(f"PASS: {FIXTURE} matches {SOURCE_ANCHOR}")
        return 0

    fixture_path.parent.mkdir(parents=True, exist_ok=True)
    fixture_path.write_bytes(expected)
    print(f"regenerated {FIXTURE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
