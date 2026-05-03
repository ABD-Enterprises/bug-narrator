#!/usr/bin/env python3

from __future__ import annotations

import argparse
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
    parser.add_argument("--changelog", default="CHANGELOG.md", help="Path to CHANGELOG.md")
    parser.add_argument("--output", default="build/release-summary.md", help="Path to the generated Markdown summary")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    changelog_path = (repo_root / args.changelog).resolve()
    output_path = (repo_root / args.output).resolve()

    changelog_text = changelog_path.read_text()
    unreleased_bullets = extract_unreleased_bullets(changelog_text)
    version = args.version or "unversioned"
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
            "## Tracker Context",
            "- Active bugs, risks, and release blockers live in GitHub Issues.",
            "- Historical phase context lives in `docs/roadmap/roadmap.md`.",
            "- This summary seed is changelog-driven and must be reviewed against the current issue tracker before release.",
        ]
    )

    lines.extend(
        [
            "",
            "## Human Review Required",
            "- Confirm the `Unreleased` changelog bullets describe only user-visible release changes before publishing.",
            "- Confirm the current GitHub Issues backlog does not contain an unresolved release blocker for the target release.",
            "- Review signing, notarization, and QA gates before using this summary in public release notes.",
            "",
        ]
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
