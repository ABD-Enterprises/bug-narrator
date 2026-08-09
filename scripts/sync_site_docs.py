#!/usr/bin/env python3
"""Generate the Docusaurus doc mirrors from their canonical repo sources.

The site copy of the user manual used to claim "This site page mirrors the
canonical user manual in the repository" while being a separately hand-written
document that had drifted since 2026-05-23 (#964). Either the claim is true or
it should not be made; this makes it true and gives CI a way to keep it true.

Repo-relative links are rewritten to absolute GitHub URLs, because a path that
resolves inside docs/ does not resolve under the site's routing.

Usage:
  scripts/sync_site_docs.py            # regenerate the mirrors
  scripts/sync_site_docs.py --check    # fail if a mirror is stale
"""
import pathlib
import re
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
BLOB = "https://github.com/ABD-Enterprises/bug-narrator/blob/main"

# canonical source -> generated site mirror
MIRRORS = {
    "docs/user/user-manual.md": "site/docs/user/user-manual.md",
}

BANNER = (
    "<!-- GENERATED FILE — DO NOT EDIT.\n"
    "     Source: {source}\n"
    "     Regenerate with: scripts/sync_site_docs.py\n"
    "     Checked by scripts/validate.sh; edit the source instead. -->\n\n"
)


def rewrite_links(markdown: str, source: str) -> str:
    """Point repo-relative markdown links at GitHub so they resolve on the site."""
    source_dir = pathlib.PurePosixPath(source).parent

    def replace(match: re.Match) -> str:
        label, target = match.group(1), match.group(2)
        if re.match(r"^[a-z]+:|^#|^/", target):
            return match.group(0)
        resolved = pathlib.PurePosixPath(str(source_dir / target))
        parts: list[str] = []
        for part in resolved.parts:
            if part == "..":
                if parts:
                    parts.pop()
            elif part != ".":
                parts.append(part)
        return f"[{label}]({BLOB}/{'/'.join(parts)})"

    return re.sub(r"\[([^\]]+)\]\(([^)]+)\)", replace, markdown)


def render(source: str) -> str:
    body = (REPO_ROOT / source).read_text(encoding="utf-8")
    return BANNER.format(source=source) + rewrite_links(body, source)


def main() -> int:
    check = "--check" in sys.argv[1:]
    stale: list[str] = []

    for source, mirror in MIRRORS.items():
        expected = render(source)
        mirror_path = REPO_ROOT / mirror
        current = mirror_path.read_text(encoding="utf-8") if mirror_path.exists() else None

        if current == expected:
            continue
        if check:
            stale.append(f"{mirror} is stale relative to {source}")
            continue

        mirror_path.parent.mkdir(parents=True, exist_ok=True)
        mirror_path.write_text(expected, encoding="utf-8")
        print(f"regenerated {mirror}")

    if stale:
        for line in stale:
            print(f"FAIL: {line}", file=sys.stderr)
        print("Run scripts/sync_site_docs.py and commit the result.", file=sys.stderr)
        return 1

    print("PASS: site doc mirrors match their canonical sources.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
