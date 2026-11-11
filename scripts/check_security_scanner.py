#!/usr/bin/env python3
"""Validate the reviewed scanner/rules snapshot before scanning."""
import hashlib
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
folder = root / "security/semgrep"
lock = json.loads((folder / "lock.json").read_text())
if not re.fullmatch(r"semgrep/semgrep:" + re.escape(lock["version"]) + r"@sha256:[0-9a-f]{64}", lock["image"]):
    raise SystemExit("FAIL: scanner image must lock the declared version by digest")
if hashlib.sha256((folder / "rules.yaml").read_bytes()).hexdigest() != lock["rules_sha256"]:
    raise SystemExit("FAIL: scanner rules differ from the reviewed snapshot")
print("PASS: security scanner and rules snapshot agree")
