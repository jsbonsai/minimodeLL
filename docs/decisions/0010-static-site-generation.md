# ADR 0010: Static website generated from repository Markdown with a minimal Python build

Status: Accepted (2026-09-23). Deployment pending first run on `main`.

## Context

The owner supplied a complete brand kit and asked for a branded README and a GitHub Pages site that showcases the project as a portfolio piece, with the repository documentation readable on the web. [docs/website-plan.md](../website-plan.md) required: no second copy of architecture, deployment, policy, or readiness content; pinned dependencies; local fonts with their license; light/dark via `prefers-color-scheme`; accessibility; no third-party runtime dependencies, analytics, or service worker; publication from reviewed `main` commits through GitHub Actions.

## Decision

- **Source of truth stays in Markdown.** `site/build.py` renders the documents listed in `site/config.json` at build time. Rendered pages carry an "Edit this page" link to the source file. Nothing under `site/` duplicates documentation prose.
- **Generator: Python-Markdown 3.7**, pinned by version in `site/requirements.txt` and by sha256 in `site/requirements-lock.txt` (`--require-hashes` in CI). It is a single pure-Python dependency with the extensions needed (fenced code, tables, heading anchors) and the repository already uses Python for packaging and profile scripts. No general-purpose Markdown parser is written in this repo.
- **Landing and 404 pages are hand-authored HTML** with a handful of `{{PLACEHOLDER}}` tokens (product name and version from `Sources/LocalAgentCore/Resources/Branding.json`, URLs from `site/config.json`). Nav and footer are shared partials.
- **Links are rewritten deterministically.** A relative Markdown link whose target is a rendered page becomes a site link with its fragment preserved; any other repository path links to GitHub (`blob/` for links, `raw/` for images). This keeps links to Swift sources, scripts, and excluded working documents valid.
- **Publication: GitHub Actions with the official Pages actions.** `pages.yml` builds on pushes to `main` that touch site or documentation paths and on manual dispatch; pull requests build and run `site/check.py` but do not deploy. Only the deploy job has `pages: write` and `id-token: write`. No `gh-pages` branch.
- **Presentation, not evidence.** Site copy must match `docs/project-state.md`; capability wording uses the same evidence levels. The site does not claim a deployment, benchmark, or certification the repository has not recorded.

## Alternatives considered

- **MkDocs / Material for MkDocs, Docusaurus, Astro, Jekyll (GitHub's default).** Richer navigation and search, but each brings a theme system, plugin surface, or Node toolchain that is heavier than a landing page plus ~25 rendered documents needs, and each would either hide or fight the supplied brand tokens. Jekyll's default build would also require Liquid-safe Markdown and a Ruby theme to match the brand.
- **Node `marked`/`markdown-it` via `npx`.** Equivalent capability; Python was chosen because the repository's scripting is already Python and a hash-pinned single wheel is simpler to audit.
- **Hand-written HTML for docs too.** Rejected: guaranteed drift from the Markdown sources.
- **Branch-based `gh-pages` publishing.** Rejected: an extra write-token workflow and artifact branch with no benefit over the Actions deployment.

## Consequences

- Adding a document is a one-line config change; removing or renaming one changes its URL, so slugs should be treated as stable.
- Mermaid blocks in Markdown render as labeled source (no client-side Mermaid runtime). The landing page carries a hand-drawn inline SVG architecture diagram instead.
- Search is not provided in the initial version; the grouped sidebar is the navigation.
- The build is verified by `site/check.py` (links, fragments, placeholders, head metadata) and by local headless-browser inspection recorded in session records. Live deployment checks must be recorded after the first run on `main`.
