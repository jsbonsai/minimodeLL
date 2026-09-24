# 2026-09-23/24: coordinator — merges, review fixes, issue triage

Role: integrate the day's parallel streams into `main` and the shared GitHub project surface (labels, milestones, issues), then hand off to the docs-integration stream for `docs/handoff.md`, `docs/project-state.md`, `docs/backlog.md`, `CHANGELOG.md`, `docs/sessions/README.md` and `docs/roadmap.md`. This record documents that integration work itself; it does not duplicate the per-stream findings already recorded in each stream's own session file.

## Merges (chronological, all against `main`, none force-pushed)

| PR | Branch | Title | Merged | Notes |
| --- | --- | --- | --- | --- |
| [#9](https://github.com/jsbonsai/minimodeLL/pull/9) | `feat/brand-assets` | Integrate Twin L branding across the macOS app | 2026-09-24T00:18:20Z | UI/resource only; see `docs/sessions/2026-09-23-brand-assets.md`. |
| [#14](https://github.com/jsbonsai/minimodeLL/pull/14) | `chore/github-org-and-iru` | Organize GitHub roadmap and rename Kandji to Iru | 2026-09-24T00:46:06Z | See `docs/sessions/2026-09-23-chore-github-org-and-iru.md`. |
| [#16](https://github.com/jsbonsai/minimodeLL/pull/16) | `feat/site-and-readme` | Branded README and GitHub Pages site | 2026-09-24T01:00:20Z | See `docs/sessions/2026-09-23-site-and-readme.md`. |
| [#19](https://github.com/jsbonsai/minimodeLL/pull/19) | `feat/runtime-lifecycle` | WORK-001: app-owned bundled llama-server runtime (readiness slice) | 2026-09-24T01:06:11Z | See `docs/sessions/2026-09-23-runtime.md`. |
| [#20](https://github.com/jsbonsai/minimodeLL/pull/20) | `feat/model-catalog` | WORK-002: verified model manifest, download, and first real model | 2026-09-24T01:51:38Z | Stacked on #19; see `docs/sessions/2026-09-23-model-catalog.md`. |

All five are `MERGED` per `gh pr view <n>`; no open PRs remain (`gh pr list --state open` is empty as of this record). No branch was rebased or force-pushed to merge; ordinary merge commits were used (`git log --oneline` on `main` shows `Merge pull request #N ...` for each).

## Review findings and fixes applied before merging #19 and #20

Two runtime/store bugs were found reviewing the stacked branches before merge and fixed directly on the feature branches (not squashed into the original commits, so each stream's own session record and validation numbers still describe the code as they left it):

1. **Shared runtime startup cancelled by one waiter** (commit [`e246d4c`](https://github.com/jsbonsai/minimodeLL/commit/e246d4c) on `feat/runtime-lifecycle`, before merging #19). `RuntimeManager.acquire()` shares one startup `Task` across concurrent callers; the original `withTaskCancellationHandler` cancelled that shared task the moment *any* single waiter's `Task` was cancelled, so one caller giving up (e.g. a UI task timeout) could abort startup for every other caller still waiting on the same launch. Fixed by tracking waiter identity (`startWaiters: Set<UUID>`) and cancelling the shared startup only once every waiter has cancelled. Regression test `cancellingOneWaiterDoesNotAbortSharedStartup` added to `RuntimeTests.swift` (starts a slow fake host, cancels the first of two concurrent `acquire()` calls, asserts the second still completes and only one process was launched).
2. **Complete-but-unverified partial download re-requested from the network** (commit [`79494bf`](https://github.com/jsbonsai/minimodeLL/commit/79494bf) on `feat/model-catalog`, before merging #20). If a previous `ModelStore` download wrote every byte of `.partial` but the app quit/crashed before hash verification, resume issued a `Range: bytes=<size>-` request (offset == total size). Some HTTP servers (confirmed behavior class, not this project's server) answer an empty/zero-length range with the **full** body instead of `416`, which would silently re-download and re-buffer a multi-gigabyte file, or, if not guarded elsewhere, misinterpret the response. Fixed by checking `offset == artifact.sizeBytes` before issuing any request and verifying/promoting the existing partial file locally instead. Regression test `completePartialIsVerifiedWithoutNetwork` added to `ModelStoreTests.swift`, asserting `transport.callCount == 0` when the partial file is already complete.

Both fixes shipped inside PR #19 / PR #20 respectively (not as separate PRs), each with its own commit message and an added test; `swift test` locally reflected 37/37 and 54/54 at the time (see each stream's session record), and both fixes are additionally covered by the post-merge hosted CI runs below. No other correctness issues were found in review; packaging, entitlements, and documentation from both streams were accepted as submitted.

## GitHub issue/label/milestone triage

Ran independently of code review, using `gh label create`, `gh api .../milestones`, `gh issue create`, and `gh issue edit`:

- **Labels** (27 total beyond GitHub's defaults): area:`runtime`/`models`/`mcp`/`policy`/`mdm`/`ui`/`site`/`packaging`/`audit` (9), type:`feature`/`security`/`docs`/`validation` (4), priority:`p1`/`p2`/`p3` (3), `blocked:owner-input` (1) — created in `chore/github-org-and-iru` (PR #14) and applied to issues #1–#22 after later issues existed.
- **Milestones**: `v0.2 Working local demo`, `v0.3 Enterprise pilot`, `v0.4 Product polish` (created in PR #14; descriptions in the milestone list at `gh api repos/jsbonsai/minimodeLL/milestones`).
- **Issues #10–#13** (opened by the `chore/github-org-and-iru` stream) were renamed and relabeled to fit the `WORK-NNN` numbering used by #1–#8, since they are the same kind of tracked work item: #10 → **WORK-009** (Raycast-inspired UI/UX redesign), #11 → **WORK-010** (connect first live HTTPS MCP server), #12 → **WORK-011** (Iru (formerly Kandji) sandbox validation), #13 → **WORK-012** (GitHub Pages site and branded README). Bodies were kept; only titles/labels/milestones changed. WORK-009 was moved from the `v0.4 Product polish` milestone (its original placement) to `v0.2 Working local demo`, because the owner's steering (relayed via the workflow: Raycast-style design sprint running now, before further real-service testing) makes it current work, not v0.4 polish; it keeps `priority:p2` since it is not the gating item for the v0.2 demo.
- **New issues opened**, matching owner ideas relayed for today's work and not yet tracked:
  - [#15](https://github.com/jsbonsai/minimodeLL/issues/15) **WORK-013** — MCP governance: stdio servers, user-added server controls, an MCP access-request flow. `area:mcp, area:policy, type:feature, priority:p3`, no milestone (explicitly late-backlog per the issue body: "not P1").
  - [#17](https://github.com/jsbonsai/minimodeLL/issues/17) **WORK-014** — Tool context control: per-task tool scoping, deferred tool loading, a tool proxy. `area:mcp, type:feature, priority:p3`, no milestone ("explore later, not P1").
  - [#18](https://github.com/jsbonsai/minimodeLL/issues/18) **WORK-015** — MDM adoption kit: least-friction Jamf and Iru deployment (signed/notarized PKG, preference manifests, silent install/uninstall, pre-provisioned model PKG). `area:mdm, area:packaging, type:feature, priority:p2`, milestone `v0.3 Enterprise pilot`.
  - [#21](https://github.com/jsbonsai/minimodeLL/issues/21) **WORK-016** — LAN / remote OpenAI-compatible inference servers (LM Studio, Ollama, or llama-server on the owner's M2 Max). `area:runtime, area:policy, type:feature, priority:p1`, milestone `v0.2 Working local demo` ("Planned — next sprint" per the issue body).
  - [#22](https://github.com/jsbonsai/minimodeLL/issues/22) **WORK-017** — MCP server management in Settings: CRUD, custom headers, auth modes. `area:mcp, area:ui, type:feature, priority:p1`, milestone `v0.2 Working local demo` ("Planned — next sprint").
- Verified final state with `gh issue list --state all --json number,title,labels,milestone,state`: 22 issues, all open, numbering and milestones as above. No issue was closed or deleted.

## GitHub Pages verification and repository homepage

- `gh api repos/jsbonsai/minimodeLL/pages` → `build_type: workflow`, `html_url: https://jsbonsai.github.io/minimodeLL/`, `https_enforced: true`.
- `gh run list --workflow pages.yml --limit 10`: the `push`-triggered deploy run for the PR #16 merge commit (`15163e9`), [run 35945059549](https://github.com/jsbonsai/minimodeLL/actions/runs/35945059549), completed `success` in 27s. Earlier `pull_request` runs (build+check only, deploy skipped by design) also succeeded.
- `curl -sI https://jsbonsai.github.io/minimodeLL/` → `HTTP/2 200`, served by GitHub's edge (Varnish), `last-modified` matching the deploy time. **The site is live.**
- Because it is live, ran `gh repo edit jsbonsai/minimodeLL --homepage https://jsbonsai.github.io/minimodeLL/`; `gh api repos/jsbonsai/minimodeLL --jq '.homepage'` now returns the URL. The repository description and topics set by the `chore/github-org-and-iru` stream were left as-is (still include the legacy `kandji` topic for discoverability, alongside `jamf`).
- The social preview image (`design-assets/minimodeLL-brand/social/banner-1200x630.png`) was **not** uploaded — that remains a UI-only, owner-side action (Settings → General → Social preview) and no API exists for it.

## Post-merge hosted CI, main branch

`gh run list --branch main --limit 10`, at the time of this record:

| Merge commit | Workflow | Result | Run |
| --- | --- | --- | --- |
| `2560d69` (pre-day baseline, "Fix commit hash in CI record") | macOS validation | success | 35936172136 |
| PR #9 merge | macOS validation | success | 35939433913 |
| PR #19 merge | macOS validation | success | 35944691612 |
| PR #20 merge | macOS validation | success | 35944755184 |
| PR #16 merge | macOS validation | success | 35945059482 |
| PR #16 merge | GitHub Pages (deploy) | success | 35945059549 |

The PR #16 merge still triggered `macOS validation` even though it only touched docs/site content, because the merge also edited `.github/workflows/ci.yml` itself (extending `paths-ignore`), and a workflow's own `paths-ignore` does not exempt edits to that same file — expected, not a bug (already noted in the site stream's own session record). No CI run on `main` is currently failing.

## Findings not yet fixed (recorded for the backlog, not fixed by this integration)

- `docs/architecture.md`, `docs/code-map.md`, `docs/validation-results.md`, and `docs/website-plan.md` still say "Kandji" in prose rather than "Iru (formerly Kandji)"; the rename stream (`chore/github-org-and-iru`) explicitly scoped itself to six other files and left these for later, and they are outside this docs-integration stream's file list too. Left as a follow-up rather than edited out-of-scope.
- `docs/decisions/README.md`'s status column for ADR 0010 still reads "first deployment pending" even though the deployment above is now live; also left for whichever stream next touches the ADR index, since it is outside this stream's six-file scope.
- The GitHub Project board (`gh project create`) is still blocked on token scope; see `docs/handoff.md` for the exact command the owner needs to run. Not something an agent token can grant itself.

## Validation actually run by this integration pass

- `gh pr view`/`gh pr list`/`gh issue list`/`gh issue view`/`gh api .../milestones`/`gh label list` — read-only fact gathering, all shown above.
- `gh run list` / `gh run watch 35945059482` — confirmed the in-flight post-merge CI run on `main` finished `success` before writing this record.
- `curl -sI https://jsbonsai.github.io/minimodeLL/` — confirmed live (`200`).
- `gh repo edit --homepage` and `gh api repos/.../pages` — confirmed the homepage field was actually set, not just requested.
- Did **not** run `swift test`, packaging, or diagnostics in this pass: no source/config file was changed by this stream, only documentation and GitHub metadata. The cited hosted CI runs above are the evidence for the merged code, not a claim that this session re-ran them.

## Handoff to docs-integration stream

This record captures the facts; `docs/handoff.md`, `docs/project-state.md`, `docs/backlog.md`, `CHANGELOG.md`, `docs/sessions/README.md` and `docs/roadmap.md` are updated in the same branch (`docs/integrate-v02`) as this record, using exactly the state documented above plus each stream's own "Suggested coordinator integration" section.
