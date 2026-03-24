#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path


def extract_unreleased_bullets(changelog_text: str) -> list[str]:
    lines = changelog_text.splitlines()
    capture = False
    bullets: list[str] = []

    for line in lines:
        if line.startswith("## Unreleased"):
            capture = True
            continue
        if capture and line.startswith("## "):
            break
        if capture and line.startswith("- "):
            bullets.append(line[2:].strip())

    return bullets


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a BugNarrator release summary seed.")
    parser.add_argument("--version", default=None, help="Target release version or tag")
    parser.add_argument("--state", default="docs/roadmap/state.json", help="Path to roadmap state.json")
    parser.add_argument("--changelog", default="CHANGELOG.md", help="Path to CHANGELOG.md")
    parser.add_argument("--output", default="build/release-summary.md", help="Path to the generated Markdown summary")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    state_path = (repo_root / args.state).resolve()
    changelog_path = (repo_root / args.changelog).resolve()
    output_path = (repo_root / args.output).resolve()

    state = json.loads(state_path.read_text())
    changelog_text = changelog_path.read_text()
    unreleased_bullets = extract_unreleased_bullets(changelog_text)
    unresolved_risks = [risk for risk in state.get("risks", []) if risk.get("status") != "resolved"]
    completed_phases = state.get("completed_phases", [])[-5:]
    version = args.version or state.get("version", "unversioned")
    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    lines = [
        "# BugNarrator Release Summary Seed",
        "",
        f"- Target version/tag: `{version}`",
        f"- Generated at: `{generated_at}`",
        f"- Source changelog section: `CHANGELOG.md -> Unreleased`",
        "",
        "## Candidate Changes",
    ]

    if unreleased_bullets:
        lines.extend(f"- {bullet}" for bullet in unreleased_bullets)
    else:
        lines.append("- No unreleased changelog bullets were found.")

    lines.extend(
        [
            "",
            "## Recently Completed Phases",
        ]
    )

    if completed_phases:
        for phase in completed_phases:
            lines.append(f"- `{phase['id']}` {phase['name']}: {phase['summary']}")
    else:
        lines.append("- No completed phases are recorded in roadmap state.")

    lines.extend(
        [
            "",
            "## Unresolved Risks",
        ]
    )

    if unresolved_risks:
        for risk in unresolved_risks:
            lines.append(
                f"- `{risk['id']}` ({risk['severity']}): {risk['description']} "
                f"Planned in `{risk['phase_association']}`."
            )
    else:
        lines.append("- No unresolved risks are recorded in roadmap state.")

    lines.extend(
        [
            "",
            "## Human Review Required",
            "- Confirm the `Unreleased` changelog bullets describe only user-visible release changes before publishing.",
            "- Confirm the unresolved risks listed above are acceptable for the target release.",
            "- Review signing, notarization, and QA gates before using this summary in public release notes.",
            "",
        ]
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
