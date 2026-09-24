#!/usr/bin/env python3
"""Build the minimodeLL GitHub Pages site.

Static, dependency-light generator:

* `site/index.html` and `site/404.html` are hand-authored pages with a few
  `{{PLACEHOLDER}}` tokens.
* Repository Markdown documents listed in `site/config.json` are rendered with
  Python-Markdown (pinned in `site/requirements.txt`) into `docs/<slug>/index.html`
  using `site/templates/doc.html`. Content is never duplicated in the site tree.
* Relative Markdown links are rewritten: targets that are part of the site link
  to the rendered page (fragments preserved); anything else links to the file on
  GitHub, so links to Swift sources, scripts, or excluded docs never 404.
* Product name and version come from `Sources/LocalAgentCore/Resources/Branding.json`;
  URLs and the tagline come from `site/config.json`.

Usage:  python3 site/build.py [--out build/site]
"""

from __future__ import annotations

import argparse
import html
import json
import os
import posixpath
import re
import shutil
import sys
from pathlib import Path

try:
    import markdown  # type: ignore
except ImportError:  # pragma: no cover - the workflow installs the pinned version
    sys.exit("Python-Markdown is required: pip install -r site/requirements.txt")

SITE_DIR = Path(__file__).resolve().parent
REPO_DIR = SITE_DIR.parent

MD_EXTENSIONS = ["fenced_code", "tables", "sane_lists", "toc", "md_in_html"]
MD_EXTENSION_CONFIGS = {
    "toc": {
        "permalink": "#",
        "permalink_class": "headerlink",
        "permalink_title": "Link to this section",
        "toc_depth": "2-4",
    }
}

SCHEME_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")
ATTR_RE = re.compile(r'(<(a|img|source)\b[^>]*?\b(href|src|srcset)=")([^"]*)(")', re.IGNORECASE)
TAG_RE = re.compile(r"<[^>]+>")


class Page:
    def __init__(self, group: str, spec: dict):
        self.group = group
        self.source = spec["source"]  # repo-relative path
        self.slug = spec["slug"]  # e.g. "architecture", "index", "decisions/0001-x"
        self.title = spec["title"]
        parts = self.slug.split("/")
        if parts[-1] == "index":
            parts = parts[:-1]
        self.dir_parts = ["docs", *parts]
        self.out_rel = "/".join([*self.dir_parts, "index.html"])
        # URL of the page directory relative to the site root, with trailing slash.
        self.url_rel = "/".join(self.dir_parts) + "/"
        self.root = "../" * len(self.dir_parts)


def load_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as fh:
        return json.load(fh)


def render_placeholders(text: str, ctx: dict) -> str:
    def repl(match: re.Match) -> str:
        key = match.group(1)
        if key not in ctx:
            raise KeyError(f"unknown placeholder {{{{{key}}}}}")
        return ctx[key]

    return re.sub(r"\{\{([A-Z_]+)\}\}", repl, text)


def repo_relative(source: str, target: str) -> str:
    """Resolve a link target relative to the Markdown source file, repo-rooted."""
    base_dir = posixpath.dirname(source)
    joined = posixpath.normpath(posixpath.join(base_dir, target)) if base_dir else posixpath.normpath(target)
    return joined.lstrip("./")


def rewrite_links(rendered: str, page: Page, pages_by_source: dict[str, Page], cfg: dict) -> str:
    repo_url = cfg["repoUrl"].rstrip("/")
    branch = cfg["defaultBranch"]

    def repl(match: re.Match) -> str:
        prefix, tag, attr, value, suffix = match.groups()
        value_unescaped = html.unescape(value)
        if not value_unescaped or value_unescaped.startswith("#") or SCHEME_RE.match(value_unescaped) or value_unescaped.startswith("//"):
            return match.group(0)
        path, _, fragment = value_unescaped.partition("#")
        target = repo_relative(page.source, path)
        if tag.lower() == "a" and target in pages_by_source:
            dest = pages_by_source[target]
            new = page.root + dest.url_rel
            if dest is page:
                new = "./"
            if fragment:
                new += "#" + fragment
        elif tag.lower() in ("img", "source"):
            new = f"{repo_url}/raw/{branch}/{target}"
        else:
            new = f"{repo_url}/blob/{branch}/{target}"
            if fragment:
                new += "#" + fragment
        return f"{prefix}{html.escape(new, quote=True)}{suffix}"

    return ATTR_RE.sub(repl, rendered)


def wrap_tables(rendered: str) -> str:
    return rendered.replace("<table>", '<div class="table-wrap"><table>').replace("</table>", "</table></div>")


def first_paragraph(rendered: str, fallback: str) -> str:
    match = re.search(r"<p>(.*?)</p>", rendered, re.DOTALL)
    if not match:
        return fallback
    text = html.unescape(TAG_RE.sub("", match.group(1))).strip()
    text = re.sub(r"\s+", " ", text)
    if len(text) > 200:
        text = text[:197].rstrip() + "..."
    return text or fallback


def sidebar_html(groups: list[tuple[str, list[Page]]], current: Page) -> str:
    out = [f'<a class="back" href="{current.root}"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M19 12H5M11 18l-6-6 6-6"/></svg>Back to overview</a>']
    for group, pages in groups:
        out.append(f"<h4>{html.escape(group)}</h4><ul>")
        for p in pages:
            aria = ' aria-current="page"' if p is current else ""
            href = "./" if p is current else current.root + p.url_rel
            out.append(f'<li><a href="{href}"{aria}>{html.escape(p.title)}</a></li>')
        out.append("</ul>")
    return "\n".join(out)


def build(out_dir: Path) -> int:
    cfg = load_json(SITE_DIR / "config.json")
    brand = load_json(REPO_DIR / cfg["brandingJson"])
    name = brand["displayName"]
    version = brand.get("version", "")
    site_url = cfg["siteUrl"].rstrip("/") + "/"

    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)

    base_ctx = {
        "NAME": html.escape(name),
        "VERSION": html.escape(version),
        "SITE_URL": site_url,
        "REPO_URL": cfg["repoUrl"].rstrip("/"),
        "DESCRIPTION": html.escape(cfg["description"], quote=True),
        "TAGLINE": html.escape(cfg["tagline"]),
        "CUR_HOME": "",
        "CUR_DOCS": "",
    }
    nav_tpl = (SITE_DIR / "templates" / "nav.html").read_text(encoding="utf-8")
    footer_tpl = (SITE_DIR / "templates" / "footer.html").read_text(encoding="utf-8")
    doc_tpl = (SITE_DIR / "templates" / "doc.html").read_text(encoding="utf-8")

    def page_ctx(root: str, **extra: str) -> dict:
        ctx = dict(base_ctx, ROOT=root, **extra)
        ctx["NAV"] = render_placeholders(nav_tpl, ctx)
        ctx["FOOTER"] = render_placeholders(footer_tpl, ctx)
        return ctx

    # --- static pages and assets ---
    shutil.copytree(SITE_DIR / "assets", out_dir / "assets")
    for static in ("index.html", "404.html"):
        text = (SITE_DIR / static).read_text(encoding="utf-8")
        # Pages serves 404.html at whatever URL was requested, so its links must be absolute.
        root = site_url if static == "404.html" else "./"
        (out_dir / static).write_text(render_placeholders(text, page_ctx(root)), encoding="utf-8")

    manifest = {
        "name": name,
        "short_name": name,
        "start_url": "./",
        "icons": [
            {"src": "assets/icon-192.png", "sizes": "192x192", "type": "image/png"},
            {"src": "assets/icon-512.png", "sizes": "512x512", "type": "image/png"},
            {"src": "assets/icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable"},
        ],
        "theme_color": "#16181D",
        "background_color": "#F2F3EF",
        "display": "browser",
    }
    (out_dir / "site.webmanifest").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (out_dir / ".nojekyll").write_text("", encoding="utf-8")
    (out_dir / "robots.txt").write_text(f"User-agent: *\nAllow: /\nSitemap: {site_url}sitemap.xml\n", encoding="utf-8")

    # --- documentation pages ---
    groups: list[tuple[str, list[Page]]] = []
    for group in cfg["docs"]:
        groups.append((group["group"], [Page(group["group"], spec) for spec in group["pages"]]))
    all_pages = [p for _, ps in groups for p in ps]
    pages_by_source = {p.source: p for p in all_pages}

    urls = [site_url]
    problems = 0
    for page in all_pages:
        src_path = REPO_DIR / page.source
        if not src_path.is_file():
            print(f"error: missing source {page.source}", file=sys.stderr)
            problems += 1
            continue
        md = markdown.Markdown(extensions=MD_EXTENSIONS, extension_configs=MD_EXTENSION_CONFIGS, output_format="html5")
        rendered = md.convert(src_path.read_text(encoding="utf-8"))
        rendered = wrap_tables(rewrite_links(rendered, page, pages_by_source, cfg))
        canonical = site_url + page.url_rel
        ctx = page_ctx(
            page.root,
            CUR_DOCS=' aria-current="page"',
            TITLE=html.escape(page.title),
            PAGE_DESCRIPTION=html.escape(first_paragraph(rendered, cfg["description"]), quote=True),
            CANONICAL=canonical,
            SOURCE=html.escape(page.source),
            EDIT_URL=f"{cfg['repoUrl'].rstrip('/')}/edit/{cfg['defaultBranch']}/{page.source}",
            SIDEBAR=sidebar_html(groups, page),
            CONTENT=rendered,
        )
        out_path = out_dir / page.out_rel
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(render_placeholders(doc_tpl, ctx), encoding="utf-8")
        urls.append(canonical)
        print(f"  {page.source} -> {page.out_rel}")

    sitemap = ['<?xml version="1.0" encoding="UTF-8"?>', '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">']
    sitemap += [f"  <url><loc>{html.escape(u)}</loc></url>" for u in urls]
    sitemap.append("</urlset>")
    (out_dir / "sitemap.xml").write_text("\n".join(sitemap) + "\n", encoding="utf-8")

    print(f"built {len(all_pages)} documentation pages into {out_dir}")
    return 1 if problems else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", default=str(REPO_DIR / "build" / "site"), help="output directory (default: build/site)")
    args = parser.parse_args()
    return build(Path(args.out).resolve())


if __name__ == "__main__":
    sys.exit(main())
