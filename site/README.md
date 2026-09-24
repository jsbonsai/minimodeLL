# Website source

This directory is the source of the GitHub Pages site. It is a small static build with no framework: hand-authored HTML for the landing and 404 pages, a Python-Markdown render of selected repository documents, and the supplied brand assets.

| Path | Purpose |
| --- | --- |
| `index.html`, `404.html` | Landing page and missing-page route; `{{PLACEHOLDER}}` tokens are filled at build time |
| `templates/nav.html`, `templates/footer.html` | Shared chrome injected into every page |
| `templates/doc.html` | Documentation page shell with grouped sidebar and "Edit this page" link |
| `config.json` | Site URL, repository URL, description, and the ordered list of documents to render |
| `assets/styles.css`, `assets/site.js` | Styles from `design-assets/minimodeLL-brand/tokens`; theme toggle, mobile nav, scroll reveal |
| `assets/fonts/` | Geist and Geist Mono variable fonts with `OFL.txt` (SIL Open Font License) |
| `assets/*.png`, `assets/favicon.*` | Curated copies of the supplied web/logo assets |
| `build.py` | Generator; reads `Sources/LocalAgentCore/Resources/Branding.json` for the product name and version |
| `check.py` | Post-build check: internal links, fragments, placeholders, required `<head>` metadata |
| `requirements.txt`, `requirements-lock.txt` | Pinned Python-Markdown (`--require-hashes` in CI) |

Documents are rendered from their Markdown sources at build time and are not copied into this directory. Relative links whose targets are rendered pages become site links; other repository links go to GitHub.

## Build locally

```sh
python3 -m venv .venv-site && .venv-site/bin/pip install -r site/requirements.txt
.venv-site/bin/python site/build.py --out build/site
.venv-site/bin/python site/check.py build/site
python3 -m http.server --directory build/site 8080   # http://localhost:8080/
```

`build/` is ignored by Git. Deployment happens through `.github/workflows/pages.yml` on pushes to `main`; pull requests only build and check.

## Adding a document

Add an entry to `config.json` under the right group with `source` (repo-relative Markdown path), `slug` (output directory under `docs/`), and `title`. Run the build and the checker.

## Constraints

- No third-party runtime dependencies, analytics, or service worker.
- Keep claims aligned with `docs/project-state.md`; the site is presentation, not evidence.
- Fonts are distributed under the OFL; keep `assets/fonts/OFL.txt` alongside them.
