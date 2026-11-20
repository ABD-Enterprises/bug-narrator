#!/usr/bin/env python3
"""Pin the shared plaintext-endpoint tables.

Both ports read `contract-fixtures/plaintext-endpoint-hosts.json` and
`contract-fixtures/plaintext-endpoint-urls.json` and assert the classifier's
answer per row. An edited row fails loudly on both ports, because the answer
stops matching. A deleted row fails silently: the loop simply has one row
fewer to check, and both suites stay green.

So nothing asserted which rows have to be there, and a later change could drop
the rows that pin security decisions — `nas.local.`, `127.1.2.3`,
`169.254.0.0`, `::ffff:0.0.0.0` — without a failing build. This script is
where the contract lives: it pins the size of each table and the rows that
carry the decisions, so adding or removing a row has to be a deliberate act.

It checks the repository's own tables, and it exercises itself against a
throwaway copy with a row deleted, so the pin cannot rot into one that
accepts a weakened table.

Usage:
  python3 scripts/check-plaintext-endpoint-tables.py
"""

import argparse
import json
import pathlib
import shutil
import sys
import tempfile

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent

HOST_TABLE = "plaintext-endpoint-hosts.json"
URL_TABLE = "plaintext-endpoint-urls.json"

# The number of rows each table has to have. Changing either is a deliberate
# act: the change and this number move together.
EXPECTED_HOST_ROWS = 73
EXPECTED_URL_ROWS = 21

# The hosts whose classification the product depends on. A table that lost one
# of these would still be the right size if another row were added in its
# place, so the size alone is not enough.
REQUIRED_HOSTS = (
    "nas.local",
    "lmstudio",
    "0x7f000001",
    "127.1.2.3",
    "169.254.0.0",
    "::ffff:0.0.0.0",
)


class ContractError(ValueError):
    """The shared plaintext-endpoint tables are not what the contract says."""


def load_table(directory: pathlib.Path, name: str) -> list[dict]:
    path = directory / name
    if not path.is_file():
        raise ContractError(f"the shared table is missing: {path}")
    try:
        entries = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise ContractError(f"{name} is not valid JSON: {error}") from error
    if not isinstance(entries, list):
        raise ContractError(f"{name} does not hold a list of rows")
    for entry in entries:
        if not isinstance(entry, dict):
            raise ContractError(f"{name} holds a row that is not an object")
    return entries


def check_directory(directory: pathlib.Path) -> None:
    hosts = load_table(directory, HOST_TABLE)
    urls = load_table(directory, URL_TABLE)

    if len(hosts) != EXPECTED_HOST_ROWS:
        raise ContractError(
            f"{HOST_TABLE} has {len(hosts)} rows; the contract says {EXPECTED_HOST_ROWS}. "
            "A row was added or removed without the contract being updated."
        )
    if len(urls) != EXPECTED_URL_ROWS:
        raise ContractError(
            f"{URL_TABLE} has {len(urls)} rows; the contract says {EXPECTED_URL_ROWS}. "
            "A row was added or removed without the contract being updated."
        )

    listed = {entry.get("host") for entry in hosts}
    for required in REQUIRED_HOSTS:
        if required not in listed:
            raise ContractError(
                f"{HOST_TABLE} no longer holds {required!r}. The rows that pin the "
                "security decisions have to stay."
            )


def exercise_itself() -> None:
    """A deleted row has to fail, or the pin says nothing."""
    with tempfile.TemporaryDirectory() as temporary:
        workspace = pathlib.Path(temporary)
        fixtures = workspace / "contract-fixtures"
        fixtures.mkdir()
        shutil.copy(REPO_ROOT / "contract-fixtures" / HOST_TABLE, fixtures)
        shutil.copy(REPO_ROOT / "contract-fixtures" / URL_TABLE, fixtures)

        entries = load_table(fixtures, HOST_TABLE)
        entries.pop()
        (fixtures / HOST_TABLE).write_text(json.dumps(entries), encoding="utf-8")

        try:
            check_directory(fixtures)
        except ContractError:
            return
        raise ContractError(
            "the check accepted a table with a row deleted, so it pins nothing"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--directory",
        type=pathlib.Path,
        default=REPO_ROOT,
        help="the repository root holding contract-fixtures/ (default: this repository)",
    )
    parser.add_argument(
        "--skip-self-check",
        action="store_true",
        help="do not exercise the check against a weakened copy of the tables",
    )
    arguments = parser.parse_args()

    try:
        # The real tables are checked first: that way a table that was changed
        # or damaged is reported with its own message, rather than with the
        # self-check's.
        check_directory(arguments.directory / "contract-fixtures")
        if not arguments.skip_self_check:
            exercise_itself()
    except ContractError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(
        f"plaintext-endpoint tables pinned: {EXPECTED_HOST_ROWS} hosts, "
        f"{EXPECTED_URL_ROWS} URLs"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
