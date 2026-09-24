#!/usr/bin/env python3
"""Check a built site: internal links and fragments resolve, no placeholders leak,
and every page has the required metadata. Exits nonzero on any problem.

Usage:  python3 site/check.py build/site
"""

from __future__ import annotations

import html
import posixpath
import re
import sys
from pathlib import Path

LINK_RE = re.compile(r'\b(?:href|src|srcset)="([^"]*)"')
PLACEHOLDER_RE = re.compile(r"\{\{[A-Z_]+\}\}")
CODE_RE = re.compile(r"<code\b.*?</code>", re.DOTALL)
ID_RE = re.compile(r'\bid="([^"]+)"')
SCHEME_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")
REQUIRED_HEAD = ["<title>", 'name="viewport"', 'rel="icon"', 'rel="stylesheet"', "<html lang="]


def ids_in(text: str) -> set[str]:
    return set(ID_RE.findall(text))


def main(root: Path) -> int:
    pages = sorted(root.rglob("*.html"))
    if not pages:
        print(f"no HTML pages found under {root}", file=sys.stderr)
        return 1
    id_cache: dict[Path, set[str]] = {}
    problems: list[str] = []

    for page in pages:
        text = page.read_text(encoding="utf-8")
        rel = page.relative_to(root).as_posix()
        if PLACEHOLDER_RE.search(CODE_RE.sub("", text)):
            problems.append(f"{rel}: unreplaced placeholder")
        for needle in REQUIRED_HEAD:
            if needle not in text:
                problems.append(f"{rel}: missing {needle}")
        page_ids = id_cache.setdefault(page, ids_in(text))
        for raw in LINK_RE.findall(text):
            value = html.unescape(raw)
            if not value or SCHEME_RE.match(value) or value.startswith("//"):
                continue
            path, _, fragment = value.partition("#")
            if path == "":
                if fragment and fragment not in page_ids:
                    problems.append(f"{rel}: missing fragment #{fragment}")
                continue
            base = page.parent.relative_to(root).as_posix()
            target_rel = posixpath.normpath(posixpath.join(base, path)) if base != "." else posixpath.normpath(path)
            if target_rel.startswith(".."):
                problems.append(f"{rel}: link escapes site root: {value}")
                continue
            target = root / target_rel
            if path.endswith("/") or target.is_dir():
                target = target / "index.html"
            if not target.is_file():
                problems.append(f"{rel}: broken link {value}")
                continue
            if fragment and target.suffix == ".html":
                target_ids = id_cache.setdefault(target, ids_in(target.read_text(encoding="utf-8")))
                if fragment not in target_ids:
                    problems.append(f"{rel}: missing fragment #{fragment} in {target.relative_to(root).as_posix()}")

    for p in problems:
        print(f"error: {p}", file=sys.stderr)
    print(f"checked {len(pages)} pages, {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1] if len(sys.argv) > 1 else "build/site").resolve()))
