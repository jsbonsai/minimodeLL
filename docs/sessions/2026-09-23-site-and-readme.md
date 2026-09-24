# 2026-09-23: branded README and GitHub Pages site (stream: site)

## Intent and scope

Owner instruction (relayed by the coordinator): showcase the supplied brand assets now with a README that carries the logo and a GitHub Pages landing/documentation site, as a career portfolio piece. Authorized: branch, commits, pushes, a PR against `main` (not merged), enabling GitHub Pages with the workflow build type, and setting the repository description and topics. Not authorized/deferred: setting the homepage URL before deployment, uploading the social preview image (UI-only), editing `docs/handoff.md`, `docs/project-state.md`, `docs/backlog.md`, or `CHANGELOG.md` (coordinator integrates those).

This session ran in parallel with other agents in separate worktrees. Branch: `feat/site-and-readme`, based on `main` at `b5d5931` (PR #9 branding merged).

## Starting checkpoint

- `docs/website-plan.md` was the approved plan (proposed, not implemented). `gh api repos/jsbonsai/minimodeLL/pages` returned 404; homepage empty; topics: jamf, kandji, litellm, local-ai, macos, mcp, swift.
- Brand kit inspected: `design-assets/minimodeLL-brand/brand-sheet.png`, `README.md`, `tokens/brand.css`, `tokens.json`, the horizontal lockup SVGs (color: ink strokes + Signal dot; reversed: paper strokes + Signal Dark dot), `web/favicon.svg` (adapts to dark mode), `web/og-image.png`, `social/banner-1200x630.png`.
- Local tooling: Python 3.13 (no `markdown` module installed system-wide), Node 23, no Chrome. A scratch venv with `Markdown==3.7` and a scratch Playwright Chromium were created outside the repository for build and screenshots.

## Changes

### README and docs map

- `README.md`: centered `<picture>` header using `lockup-horizontal-color.svg` for light and `lockup-horizontal-reversed.svg` for dark (ink `#16181D` on GitHub light `#ffffff`; paper `#F2F3EF` + `#7D96FF` on GitHub dark `#0d1117`; both pass AA by inspection of the token values), badges (CI, Pages, MIT, platform, Swift, status), one-paragraph pitch centered on IT governability (MDM-forced policy via Jamf / Iru (formerly Kandji), allowlisted models and MCP tools, human approval, content-free audit, no silent cloud fallback), a "Why" section, a brand-sheet image in the Branding section, and OFL attribution. The developer-preview disclaimer, build/config instructions, and the "Connect inference" and "Connect tools" sections are unchanged in substance. "Kandji" wording changed to "Iru (formerly Kandji)" outside those sections.
- `docs/README.md`: smaller header, website/source/start links, "Iru (formerly Kandji)" row label, website-plan row description.

### Site (`site/`)

- `index.html` (landing), `404.html`, `templates/{nav,footer,doc}.html`, `config.json`, `assets/styles.css`, `assets/site.js`, curated assets (favicons, touch icon, PWA icons, OG images, social banner, four logo SVGs), Geist and Geist Mono variable fonts with `OFL.txt`.
- Landing sections: hero (mark, tagline, CTAs, illustrative approval "task card"), why, governance flow (MDM → forced policy → app; approvals; audit), eight-card feature grid, inline SVG architecture diagram with `<title>`/`<desc>` and CSS-variable colors, status (works today vs in progress; links #1, #2, #4, #6), getting started, footer.
- Design: brand tokens as CSS custom properties; dark via `prefers-color-scheme` with an optional per-browser toggle (`localStorage`, guarded); 16px gutter at phone width; skip link; visible focus rings; `aria-current` on nav and sidebar; motion limited to a scroll reveal, a status-dot pulse, and hover lifts, all disabled under `prefers-reduced-motion`.
- `build.py` renders the 26 documents in `config.json` (docs map, development, architecture, configuration reference, code map, deployment, Jamf test plan, Iru/Kandji, security, validation plan/results, project state, decisions README + 8 ADRs, roadmap, branding, contributing, changelog, website plan). It rewrites relative links (rendered targets → site paths with fragments; other repo paths → GitHub `blob/`, images and `<source srcset>` → `raw/`), wraps tables for horizontal scroll, labels Mermaid blocks as source, and writes `sitemap.xml`, `robots.txt`, `site.webmanifest` (relative icon paths, `display: browser`, no service worker), and `.nojekyll`.
- `check.py` fails the build on broken internal links, missing fragments, leaked placeholders, or missing head metadata.
- `requirements.txt` (`Markdown==3.7`) and `requirements-lock.txt` (sha256 of the wheel and sdist; CI installs with `--require-hashes`).

### Workflows

- `.github/workflows/pages.yml`: build job (checkout@v7, setup-python@v7 / 3.12, hash-pinned install, build, check, `upload-pages-artifact@v5`), deploy job (`deploy-pages@v5`, `github-pages` environment, `pages: write` + `id-token: write` only there), `concurrency: pages`, triggers: push to `main` on site/docs/README/SECURITY/CONTRIBUTING/CHANGELOG/Branding.json/workflow paths, pull requests on the same paths (build + check only, `if: github.event_name != 'pull_request'` on deploy), `workflow_dispatch`.
- `.github/workflows/ci.yml`: `paths-ignore` extended with `site/**` and `.github/workflows/pages.yml` so website-only pushes do not run the macOS build. The existing `**/*.md` ignore already excluded README/docs changes.

### Documentation

- `docs/website-plan.md`: status block and implementation table added at the top; original plan retained below.
- `docs/decisions/0010-static-site-generation.md`: generator and publication decision; `docs/decisions/README.md` row added.
- This session record. `docs/sessions/README.md` was intentionally not edited to avoid parallel-branch conflicts; the coordinator should add the link.

## Validation actually run

| Check | Result |
| --- | --- |
| `python site/build.py --out build/site` (venv, Markdown 3.7) | Built 26 documentation pages + landing + 404; 52 files, ~1.0 MB. |
| `python site/check.py build/site` | 28 pages checked, 0 problems (after fixes below). |
| `pip install --require-hashes -r site/requirements-lock.txt` | Succeeded with the recorded hashes. |
| Headless Chromium (Playwright 1.47.2, scratch install) over a local static server: home, docs index, architecture doc, configuration reference, 404 at 1280px and 390px, light and dark, `reducedMotion: reduce` | No console errors, no failed requests, no 4xx responses, no horizontal overflow on the final build. Screenshots inspected visually in both themes at desktop and phone widths. |
| Keyboard order on the landing page (12 Tabs) | Skip link → wordmark → Governance → Architecture → Status → Docs → GitHub → theme toggle → Build the preview → Read the docs → in-copy links. |
| Fixes made from inspection | Architecture SVG sub-labels overflowed their boxes and two edge labels collided with arrows: boxes widened to 190px, labels shortened, label positions moved, and a stray arrowhead removed (CSS `marker-end` overrode the attribute; now an inline style). Docs page overflowed at 390px because the grid column was `1fr`, now `minmax(0, 1fr)`. `<source srcset>` in docs/README's picture element was not rewritten; the rewriter and checker now handle `srcset`. |

Not run: `swift test`, packaging, or any app checks (no application code changed; the CI paths-ignore change is a workflow trigger change only). The Pages workflow has not executed; `actionlint` is not installed locally, so the YAML was reviewed by eye only. GitHub's rendering of the README `<picture>` element was not observed because the branch is unmerged; it is a documented GitHub feature.

## GitHub actions taken

- Commits `d2e08e5` (site + workflows) and `718f72a` (README, docs, ADR, session record) pushed to `origin/feat/site-and-readme`.
- Pull request: https://github.com/jsbonsai/minimodeLL/pull/16 "Branded README and GitHub Pages site" (not merged by this session).
- `gh api -X POST repos/jsbonsai/minimodeLL/pages -f build_type=workflow` succeeded: `build_type: workflow`, `html_url: https://jsbonsai.github.io/minimodeLL/`, `https_enforced: true`, `status: null` (no deployment has run yet).
- `gh repo edit` set the description ("IT-governable local AI for Macs: ...") and added topics `apple-silicon`, `enterprise`, `llama-cpp`, `local-llm`, `mdm`, `swiftui` alongside the existing `jamf`, `kandji`, `litellm`, `local-ai`, `macos`, `mcp`, `swift`. The `kandji` topic was left in place for discoverability.
- Homepage URL and social preview image were **not** set (deferred until deployment; see below).
- CI on the branch: see "CI results" below.

## CI results

At commit `718f72a` (before the action-version bump in the following commit):

- `macOS validation` (push): success, https://github.com/jsbonsai/minimodeLL/actions/runs/35940909102 (2m25s). It ran because `ci.yml` itself changed; website-only pushes are ignored from now on.
- `GitHub Pages` (pull_request, build + check only, deploy skipped by design): success, https://github.com/jsbonsai/minimodeLL/actions/runs/35940982820 (build 9s, `github-pages` artifact uploaded). Annotations warned that `checkout@v4` / `setup-python@v5` target Node 20; the workflow was then bumped to `checkout@v7`, `setup-python@v7`, `upload-pages-artifact@v5`, `deploy-pages@v5` (current majors per each action's latest release). That bump is verified by the PR run that follows the next push, not by this record.
- `macOS validation` (pull_request) was still in progress when this record was written; check https://github.com/jsbonsai/minimodeLL/pull/16/checks.
- `ci.yml` still uses `actions/checkout@v4` (Node 20 deprecation warning); left for the coordinator since it is outside this stream.

## Not done / needs owner

- Merge the PR, then confirm the `GitHub Pages` workflow run and the URL GitHub reports (expected `https://jsbonsai.github.io/minimodeLL/`). Inspect the live landing page, a nested docs page, the 404 route, `sitemap.xml`, and the OG image URL.
- After deployment: `gh repo edit jsbonsai/minimodeLL --homepage https://jsbonsai.github.io/minimodeLL/`, then update the README to link the site directly.
- Social preview: Settings → General → Social preview → upload `design-assets/minimodeLL-brand/social/banner-1200x630.png` (UI only).
- Record live-site evidence in `docs/validation-results.md` and add this session to `docs/sessions/README.md`.
- Optional later: docs search, a real sanitized app screenshot in the hero once the UI stabilizes, Raycast-style UI exploration tracked in the backlog by the coordinator.

## Resume commands

```sh
git fetch origin && git checkout feat/site-and-readme
python3 -m venv .venv-site && .venv-site/bin/pip install --require-hashes -r site/requirements-lock.txt
.venv-site/bin/python site/build.py --out build/site && .venv-site/bin/python site/check.py build/site
python3 -m http.server --directory build/site 8080   # http://localhost:8080/
gh pr view --web
gh run list --workflow pages.yml --limit 5           # after merge
```
