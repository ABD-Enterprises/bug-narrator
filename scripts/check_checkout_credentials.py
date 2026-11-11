#!/usr/bin/env python3
"""Keep checkout credentials out of later workflow steps."""
import re
from pathlib import Path

import yaml


def problems(text):
    workflow = yaml.safe_load(text) or {}
    errors = []
    for job in workflow.get("jobs", {}).values():
        for step in job.get("steps", []):
            if str(step.get("uses", "")).lower().startswith("actions/checkout@"):
                if step.get("with", {}).get("persist-credentials") is not False:
                    errors.append("checkout must explicitly set persist-credentials: false")
            if re.search(r"\bgit\s+push\b", str(step.get("run", ""))):
                errors.append("workflow must not push using checkout credentials")
    return errors


def main():
    good = "jobs:\n  test:\n    steps:\n      - uses: 'actions/checkout@fixture'\n        with:\n          persist-credentials: false # deliberate\n"
    assert not problems(good)
    assert problems(good.replace("false", "true"))
    assert problems(good.replace("          persist-credentials: false # deliberate\n", ""))
    assert problems("jobs: {test: {steps: [{uses: actions/checkout@fixture}]}}")
    failures = []
    for path in sorted(Path(".github/workflows").glob("*")):
        if path.suffix in {".yml", ".yaml"}:
            failures.extend(f"{path}: {error}" for error in problems(path.read_text()))
    if failures:
        raise SystemExit("\n".join(failures))
    print("PASS: workflow checkouts do not retain credentials")


if __name__ == "__main__":
    main()
