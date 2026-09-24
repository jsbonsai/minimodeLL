# Repository branding and GitHub Pages plan

Date: 2026-09-23. Status: **implemented on branch `feat/site-and-readme`; deployment pending merge to `main`.** The sections below the status block are the original approved plan, kept for rationale.

## Implementation status (2026-09-23, site stream)

Built and verified locally; see the [session record](sessions/2026-09-23-site-and-readme.md) for the exact checks.

| Plan item | Status |
| --- | --- |
| README branding: centered `<picture>` header (color lockup on light, reversed lockup on dark), badges, pitch, "Why" section, Iru (formerly Kandji) wording | Done in `README.md`; `docs/README.md` has a smaller header plus website/source/start links. GitHub rendering of the `<picture>` element is expected but not yet observed on `main`. |
| Static site with brand tokens, Geist (OFL copied), light/dark, responsive, accessible, keyboard nav, OG/Twitter meta, favicons | Done under `site/`: hand-authored `index.html` and `404.html`, shared nav/footer partials, `assets/styles.css` derived from `tokens/brand.css`, `assets/site.js` (theme toggle, mobile nav, reduced-motion-aware reveal). |
| Landing sections: hero with mark, tagline and CTAs; governance flow; feature grid; inline SVG architecture diagram; honest status/roadmap; getting started; footer | Done. The hero "task card" is labeled illustrative. Status copy distinguishes what works today from in-progress work and links issues #1, #2, #4, #6. |
| Documentation rendered from Markdown at build time, not duplicated | Done: `site/build.py` (Python-Markdown 3.7, hash-pinned in `site/requirements-lock.txt`) renders the documents listed in `site/config.json` into `docs/<slug>/`, rewrites relative links (rendered targets become site links; everything else links to GitHub), adds heading anchors, an "Edit this page" link, sitemap, robots, manifest, `.nojekyll`. `site/check.py` verifies links, fragments, placeholders, and head metadata. Decision recorded in [ADR 0010](decisions/0010-static-site-generation.md). |
| `.github/workflows/pages.yml` with `actions/upload-pages-artifact@v5` and `actions/deploy-pages@v5`, `pages: write` / `id-token: write` on the deploy job only, `concurrency: pages`, push-to-main path filter plus `workflow_dispatch`; pull requests build and check only | Done. Not yet run on `main`; the first deployment happens after merge. `ci.yml` now ignores `site/**` and `pages.yml` so website-only changes do not trigger the macOS build. |
| Enable Pages with build type `workflow` | See the session record for the API call result. |
| Repository description and topics | See the session record. |
| Homepage URL and social preview image | Deferred until the site is deployed and inspected. Social preview is a UI-only upload: use `design-assets/minimodeLL-brand/social/banner-1200x630.png`. |
| Post-deployment checks (live URL, social image URLs, README logos on GitHub, record in validation results) | Not performed; requires merge. |

Expected URL after deployment, still not a live-site claim: `https://jsbonsai.github.io/minimodeLL/`.

## Owner request and latest instruction

The owner wants the supplied banner/logo on GitHub and in documentation, plus a branded landing page and documentation hosted through GitHub. They described a possible “PWA or SWA” and recalled seeing GitHub-hosted documentation sites. After initial discovery, the owner explicitly paused implementation and asked for a documented plan so another agent can take over. This session only records the plan. Resume implementation when the owner asks to continue.

## Starting checkpoint — observed, not assumed

- Checkout: `/Users/apple/dev/minimodel`; public repository: https://github.com/jsbonsai/minimodeLL.
- Current branch at discovery: `feat/brand-assets`, based on commit `6ed1938` (supplied native branding).
- Branding PR: https://github.com/jsbonsai/minimodeLL/pull/9. It was **open and unmerged** when inspected. Do not assume assets already exist on `main`.
- Working tree was clean before this documentation work. No website code, dependency installation, workflow, hosting branch, or Pages settings were created in this session.
- Repository default branch: `main`; homepage URL was empty.
- `gh api repos/jsbonsai/minimodeLL/pages` returned HTTP 404. Treat Pages as not configured/available at this checkpoint; recheck permissions/settings before enabling it.
- The local native app was rebuilt and restarted in the preceding branding session. This session did not change or restart it, or start any web/inference server.
- Current product remains a developer preview. No production DMG download, bundled runtime, qualified model catalog, real MCP/OAuth validation, or enrolled Jamf/Kandji validation exists.

## Proposed outcome

A public **GitHub Pages static website** with a polished single landing page and linked, readable documentation pages. GitHub Pages is the hosting product the owner likely recalls. A PWA adds installation/offline behavior, which is optional and unnecessary for this initial documentation site. “SWA” is not needed as an architectural requirement. The native macOS app remains the product; the website explains it and helps people build and contribute.

Use a small static build with repository Markdown as the documentation source. Avoid maintaining a second copy of architecture, deployment, policy, or readiness claims. No backend, account system, analytics, or runtime model connection is needed for the site.

Expected project URL, **not a live-site claim**: `https://jsbonsai.github.io/minimodeLL/`. Confirm GitHub's returned URL after publication and preserve project-path capitalization in generated links.

## 1. Repository branding

1. Add an accessible, centered logo/wordmark header to the root README. Use a GitHub-compatible `<picture>` with supplied light/dark SVG variants or another verified rendering approach. Include alt text and explicit width; avoid an enormous banner pushing the project description below the fold.
2. Add the same smaller header to `docs/README.md`, followed by clear website/documentation/source links once a site exists.
3. Keep the substantive build instructions and developer-preview disclaimer visible. A visual refresh must not hide limitations.
4. Use the supplied social banner for site Open Graph/Twitter metadata. GitHub repository **social preview** is a separate repository setting; a README image does not set it. Inspect current supported GitHub UI/API before changing it. If a UI upload is required and unavailable, document the exact asset and manual action; do not claim it was set.
5. Set the repository About/homepage URL only after a successful deployment.
6. Do not replace the owner's GitHub account avatar. A repository does not have a separate ordinary avatar setting equivalent to a profile image.

## 2. Existing asset inventory

All paths below are relative to repository root. These assets are on the branding branch; preserve the user's originals.

| Use | Supplied source |
| --- | --- |
| Light header | `design-assets/minimodeLL-brand/logo/svg/lockup-horizontal-color.svg` |
| Dark header | `design-assets/minimodeLL-brand/logo/svg/lockup-horizontal-reversed.svg` (inspect contrast before selecting) |
| Standalone mark | `design-assets/minimodeLL-brand/logo/svg/mark-color.svg`, `mark-reversed.svg` |
| Social/repository preview | `design-assets/minimodeLL-brand/social/banner-1200x630.png` |
| Website sharing | `design-assets/minimodeLL-brand/web/og-image.png`, `og-image-dark.png` |
| Browser icons | `design-assets/minimodeLL-brand/web/favicon.svg`, `favicon.ico`, `apple-touch-icon.png` |
| Optional install icons | `design-assets/minimodeLL-brand/web/icon-192.png`, `icon-512.png`, `icon-maskable-512.png` |
| Typography | `design-assets/minimodeLL-brand/fonts/Geist-Regular.otf`, `Geist-SemiBold.otf`, `Geist-Bold.otf`, `GeistMono-Regular.otf` |
| Font license | `design-assets/minimodeLL-brand/fonts/OFL.txt` — copy verbatim alongside distributed fonts |
| Palette | `design-assets/minimodeLL-brand/tokens/brand.css`, `tokens.json` |
| Brand overview | `design-assets/minimodeLL-brand/README.md`, `brand-sheet.png` |

The native app's curated resource directory is `Sources/MinimodeLL/Resources/BrandAssets/`; do not make the website depend on a built `.app`. Copy only the required web assets into the generated site. Inspect images before choosing variants. Existing SVG wordmarks contain the present name; a future rename requires artwork updates even if text configuration is centralized.

## 3. Landing page content and visual direction

Use the supplied Twin L mark, Geist, warm paper/ink palette, and blue accent. Design a restrained, readable developer tool site with generous spacing, responsive layout, real text, and a keyboard-accessible navigation bar.

Suggested page sections:

1. **Hero:** “Small tasks. On your Mac.” with a plain description of the native menu bar assistant. Show “Developer preview” prominently. Primary action: “Build the preview”; secondary: “Read the docs”; repository link in navigation.
2. **Product illustration:** a small conceptual task → approved model → approved MCP tool → concise result diagram, or a sanitized real app screenshot. Label illustrative content; never portray a mock response as a real connected integration.
3. **What it provides:** bounded requests, explicit tool approvals, approved model/provider catalogs, metadata audit, native macOS UI. Distinguish safeguards implemented today from open hardening work.
4. **Local and managed:** local inference with an existing external server today; explicitly selected LiteLLM gateway; optional shared MDM policy. Jamf is the first intended live-validation target; Kandji is best-effort with no tenant validation.
5. **Start building:** current build prerequisites and short commands sourced from the existing development documentation. No “Download DMG” button until a distributable release exists.
6. **Documentation directory:** Getting started, Architecture, Configuration, Security, Deployment, Jamf, Kandji, Validation, Contributing, Roadmap.
7. **Open development:** GitHub issues, MIT license, readiness statement, contributor entry points.

Do not promise zero cloud data transfer: HTTPS MCP services are remote and tool results go to the explicitly selected inference provider. Do not claim enterprise certification, benchmarked 16/24/32/64 GB support, or immutable audit logging.

## 4. Documentation and site build structure

Proposed layout (exact generator choice remains open):

```text
site/
  config.json             # repository URL, base path, short tagline/site metadata
  templates/              # landing and documentation shells
  styles.css              # responsive layout and supplied brand tokens
scripts/build-site.py     # if choosing the lightweight Python generator
requirements-site.txt     # pinned Markdown build dependency, if Python is chosen
build/site/               # generated output; ignored by Git
.github/workflows/pages.yml
```

A small Python Markdown-based build is a reasonable fit with existing tooling. Before implementing, compare its maintenance cost with a conventional static documentation generator; choose one and record the actual decision in an ADR. Do not build a general-purpose Markdown parser. Pin dependencies and provide one local build command.

Requirements independent of generator:

- Read `displayName` and version from `Sources/LocalAgentCore/Resources/Branding.json`; site-specific URL/tagline values live in one config file. Do not change the stable app bundle ID for a website rename.
- Render existing `docs/**/*.md` plus selected top-level README/contribution/security/license/changelog content. Keep source pages editable on GitHub with an “Edit this page” link.
- Rewrite Markdown links to published HTML when their targets are included. Links to Swift files, scripts, examples, or excluded source files should resolve to the repository, not broken website paths.
- Support fenced code, tables, heading anchors, nested document paths, and readable code overflow. Preserve relative links and fragments; root-level and nested pages must work under `/minimodeLL/`.
- Provide a documentation sidebar/grouped navigation and a clear link back to the landing page. Search can be added later; initial navigation must work without client-side JavaScript.
- Host fonts/icons locally, preserve licenses, and avoid third-party runtime dependencies.
- Include title, description, canonical URL, favicon, social metadata, and a useful 404 page. Include a sitemap if simple with the chosen generator.
- Use an explicit content/asset inclusion policy. Do not publish the whole checkout, `.git`, build logs, native binaries, configurations outside checked-in public examples, or historical PRDs as current documentation.
- No service worker in the initial version. Offline caching can make rapidly changing preview documentation stale and requires an update strategy. The supplied webmanifest is only an asset template, not proof of PWA functionality.

## 5. GitHub Pages publication

Preferred plan: GitHub Actions builds static output and publishes with the official Pages actions. Set repository Pages source to GitHub Actions when ready. Use `contents: read` for checkout/build and only grant `pages: write` / `id-token: write` to deployment. Deploy using the `github-pages` environment; serialize deployments with a concurrency group. Pull requests may build/check the site but must not deploy it. Normal publication should come from reviewed `main` commits, with optional manual dispatch.

Important dependency: PR #9 is unmerged. Inspect its status and the owner's established merge workflow before basing a website PR on its assets. Use an explicitly stacked branch/PR or wait for the asset change to land. Do not silently merge unrelated application changes to get a website workflow onto `main`.

Alternative: generated `gh-pages` branch with branch-based Pages publishing. This can bootstrap a site without a workflow on `main`, but creates an extra artifact branch and write-token workflow to maintain. Prefer the Actions route unless a concrete repository constraint justifies the alternative; document the choice. **No hosting branch was created in this session.**

After deployment, obtain the actual site URL from GitHub, inspect the live site, update the README links and repository homepage, and record the workflow run. Publication is part of the originally requested website outcome, but the latest user instruction pauses implementation at this plan.

Official references consulted on 2026-09-23:

- [Creating a GitHub Pages site](https://docs.github.com/en/pages/getting-started-with-github-pages/creating-a-github-pages-site)
- [Configuring the publishing source](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)
- [Using custom workflows with GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)

Recheck current official action versions and workflow guidance when implementing. No Pages configuration has been changed yet.

## 6. Proposed acceptance checks — not performed

When implementation resumes and checks are authorized:

- Build from a fresh checkout with documented, pinned dependencies.
- Inspect landing and documentation pages at desktop and narrow/mobile widths, light/dark appearance, and keyboard navigation. Verify contrast, focus visibility, alt text, and no horizontal page overflow.
- Verify root, nested docs, relative asset paths, source links, Markdown fragments, and a missing-page route under the real project base path.
- Confirm the generated artifact contains only intended public site content and required licensed assets.
- Check actual deployed HTML and social-image URLs, not merely a successful Actions result.
- Confirm README logos render on GitHub in both themes; verify social-preview setting separately if changed.
- Record deployment URL, commit, workflow result, observed checks, and all remaining gaps in `docs/validation-results.md` and a session record.
- Do not run Swift/model/MCP/MDM tests just for website content. Website work does not establish additional app validation.

## Exact resume instructions

1. Read `AGENTS.md`, `docs/handoff.md`, this plan, `docs/project-state.md`, and `docs/branding.md`.
2. Inspect `git status --short`, current branch/log/remotes, PR #9, recent CI, and Pages settings. Preserve other work.
3. Confirm the owner's next request is to implement the website; the last instruction in this session was documentation only.
4. Resolve the asset-branch dependency and choose a scoped website branch. Implement README branding, then the site build/landing/documentation navigation, then publishing configuration.
5. Keep app/runtime work unchanged. Update documentation and open/attach the relevant PR; report publication truthfully if merge/hosting is still pending.

The underlying next app milestone remains WORK-001 / issue #1 (bundled authenticated runtime lifecycle). The website is the owner's latest requested presentation/documentation work and should not be mistaken for completion of that milestone.
