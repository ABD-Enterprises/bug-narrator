#!/usr/bin/env python3
"""Keep checkout credentials out of later workflow steps."""
import re
from pathlib import Path


def problems(text):
    lines = text.splitlines()
    errors = []
    for i, line in enumerate(lines):
        if line.lstrip().startswith("#"):
            continue
        if re.search(r"\bgit\s+push\b", line):
            errors.append("workflow must not push using checkout credentials")
        if re.search(r"uses:\s*actions/checkout@", line):
            indent = len(line) - len(line.lstrip())
            block = []
            for following in lines[i + 1:]:
                if following.strip() and len(following) - len(following.lstrip()) < indent:
                    break
                block.append(following)
            expected = " " * (indent + 2) + "persist-credentials: false"
            if " " * indent + "with:" not in block or expected not in block:
                errors.append("checkout must explicitly set persist-credentials: false")
    return errors


def main():
    good = "  uses: actions/checkout@fixture\n  with:\n    persist-credentials: false\n"
    assert not problems(good)
    assert problems(good.replace("false", "true"))
    assert problems(good.replace("    persist-credentials: false\n", ""))
    assert problems("  uses: actions/checkout@fixture\n- name: Other\n  with:\n    persist-credentials: false")
    failures = []
    for path in sorted(Path(".github/workflows").glob("*")):
        if path.suffix in {".yml", ".yaml"}:
            failures.extend(f"{path}: {error}" for error in problems(path.read_text()))
    if failures:
        raise SystemExit("\n".join(failures))
    print("PASS: workflow checkouts do not retain credentials")


if __name__ == "__main__":
    main()
