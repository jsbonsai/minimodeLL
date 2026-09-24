# Ordered implementation backlog

Last reviewed: 2026-09-24 (coordinator integration of PRs #9, #14, #16, #19, #20). GitHub issues are the source of truth for numbering, labels and milestones; this file summarizes and orders them for an agent picking up work. Milestones: **v0.2 Working local demo**, **v0.3 Enterprise pilot**, **v0.4 Product polish**. Priority labels (`priority:p1`/`p2`/`p3`) and area labels (`area:runtime`, `area:models`, `area:mcp`, `area:policy`, `area:mdm`, `area:ui`, `area:site`, `area:packaging`, `area:audit`) are applied on GitHub; `blocked:owner-input` marks anything waiting on the owner. The handoff identifies the active task; do not interpret every item as authorization to ship a production release immediately.

## WORK-001 — Own a pinned local runtime lifecycle

Tracking: https://github.com/jsbonsai/minimodeLL/issues/1 · `area:runtime`, `priority:p1` · Milestone: v0.2

**Status: in progress.** A readiness slice merged in [PR #19](https://github.com/jsbonsai/minimodeLL/pull/19): pinned official `ggml-org/llama.cpp` prebuilt (`scripts/fetch-runtime.sh`), a `RuntimeManager` actor owning app-launched `llama-server` lifecycle (random loopback port, per-launch key, authenticated readiness, idle unload), a `minimodell-runtime-guard` supervisor that stops the server if the app dies, and a live sandboxed proof with a 135M smoke-test model (not a qualified model). See ADR [0008](decisions/0008-bundled-runtime-lifecycle.md) and `docs/sessions/2026-09-23-runtime.md`.

Remaining: a qualified real model with measured memory/latency (tracked jointly with WORK-002/WORK-005); Developer ID signing with hardened runtime on the helper and notarized DMG/PKG install (WORK-006/WORK-015); hung-inference cancellation is unmeasured (cancelling a task closes the HTTP request, but whether `llama-server` then stops generating was not observed); memory-pressure admission/unload; a GUI-level test of the readiness indicator and quit path.

## WORK-002 — Verified model artifacts and approved catalog management

Tracking: https://github.com/jsbonsai/minimodeLL/issues/2 · `area:models`, `priority:p1` · Milestone: v0.2 · Depends on WORK-001.

**Status: in progress.** A trimmed slice merged in [PR #20](https://github.com/jsbonsai/minimodeLL/pull/20), stacked on #19: a versioned `ModelCatalog`/`ModelArtifact` manifest tied into policy validation, a `ModelStore` actor (resumable HTTPS download, disk-space check, verify-before-promote SHA-256, cancel/delete/import), a Settings → Models tab, and the first real, tool-capable, openly licensed model — **Qwen3-4B-Instruct-2507 Q4_K_M** (Apache-2.0) — running live in the sandboxed bundled runtime. See ADR [0009](decisions/0009-model-artifact-manifest.md) and `docs/sessions/2026-09-23-model-catalog.md`.

Remaining: separately provisioned, read-only shared/managed artifacts (an MDM-placed directory the sandbox cannot read directly needs a design); rollback to a previous artifact version; a signed or remote catalog; garbage collection of promoted files no catalog lists; a global download queue; the Models tab and file-picker Import were not visually/UI-tested; real-network resume/redirect-rejection edge cases untested. WORK-005 should use the recorded measurements (about 1 s warm load, about 41 tok/s, peak RSS about 3.7 GB on one M1 Pro/32 GB) as a starting point, not a support claim.

## WORK-003 — Bound transport memory and prove cancellation behavior

Tracking: https://github.com/jsbonsai/minimodeLL/issues/3 · `area:mcp`, `type:security`, `priority:p2` · Milestone: v0.3

Status: open, not started. Security gate before real-service rollout; can precede WORK-001 if implementation work focuses on transport safety.

Add pre-buffer/pre-decode MCP response limits and explicit redirect/discovery trust rules. Exercise unresponsive streams, oversized replies, cancellation during connect/discovery/tool/auth, late responses and disconnect races. Ensure deadlines cannot hang indefinitely waiting for an uncooperative child task. Record uncertain external action outcomes distinctly and preserve no automatic write retries.

## WORK-004 — Qualify baseline MCP services and OAuth

Tracking: https://github.com/jsbonsai/minimodeLL/issues/4 · `area:mcp`, `type:validation`, `priority:p1`, `blocked:owner-input` · Milestone: v0.3 · Depends on WORK-003.

Status: **blocked on owner** for endpoint/service details and test accounts. See related WORK-010 below for the first concrete live MCP server, which is the more immediate unblock the owner has committed to.

## WORK-005 — Exact context budgets and fleet model qualification

Tracking: https://github.com/jsbonsai/minimodeLL/issues/5 · `area:models`, `type:validation`, `priority:p2` · Milestone: v0.3 · Depends on WORK-001/002 and representative service fixtures.

Status: open, not started, but now has a first data point to build from (WORK-002's Qwen3-4B measurements on one M1 Pro/32 GB). Count the full rendered model template with the correct tokenizer, add pressure-aware admission/unload, and exercise the owner's 16/24/32/64 GB fleet.

## WORK-006 — Validate Jamf, maintain best-effort Iru, and qualify packaging

Tracking: https://github.com/jsbonsai/minimodeLL/issues/6 · `area:mdm`, `area:packaging`, `type:validation`, `priority:p1`, `blocked:owner-input` · Milestone: v0.3 · Depends on runtime packaging and access to signing/MDM test environment.

Status: **blocked on owner.** Use the owner/coworker Jamf sandbox for the first focused enrolled-device run (`docs/jamf-test-plan.md`); Iru (formerly Kandji) remains a best-effort, unvalidated path (`docs/kandji.md`) pending vendor sandbox access (see WORK-011). Developer ID signing/notarization and clean-machine DMG/PKG install/update/rollback/uninstall are also unstarted.

## WORK-007 — Audit provenance and actionable failure outcomes

Tracking: https://github.com/jsbonsai/minimodeLL/issues/7 · `area:audit`, `priority:p2` · Milestone: v0.3

Status: open, not started.

## WORK-008 — Product polish and accessible configuration

Tracking: https://github.com/jsbonsai/minimodeLL/issues/8 · `area:ui`, `priority:p2` · Milestone: v0.4 · Depends on a working local runtime flow (now available via WORK-001/002).

Status: open, not started. Related to, but distinct from, WORK-009's Raycast-style visual redesign: this item is about approachable configuration flows and accessibility, not visual style.

## WORK-009 — Raycast-inspired UI/UX redesign

Tracking: https://github.com/jsbonsai/minimodeLL/issues/10 · `area:ui`, `priority:p2` · Milestone: **v0.2** (moved from v0.4; renamed from issue title "Raycast-inspired UI/UX redesign")

Status: **in progress — sprint 2.** Owner wants a slick, launcher-style UI: translucent vibrancy materials, global hotkey invocation, command-bar search/filter, smooth animations, keyboard-first navigation, and explicit Reduce Motion/Transparency support. Moved into the v0.2 milestone and running now as a design sprint in parallel with WORK-016/WORK-017, ahead of further real-service testing, per current owner steering (see `docs/handoff.md`). Relates to WORK-008.

## WORK-010 — Connect first live HTTPS MCP server

Tracking: https://github.com/jsbonsai/minimodeLL/issues/11 · `area:mcp`, `priority:p1`, `blocked:owner-input` · Milestone: v0.2 (renamed from "Connect first live HTTPS MCP server")

Status: **blocked on owner** for the exact endpoint, auth mode (native OAuth with redirect `org.minimodell.agent://oauth-callback`, or a Keychain bearer token) and tool names. The app supports Streamable HTTP only, not legacy HTTP+SSE. Relates to WORK-004, WORK-007.

## WORK-011 — Iru (formerly Kandji) sandbox validation

Tracking: https://github.com/jsbonsai/minimodeLL/issues/12 · `area:mdm`, `type:validation`, `priority:p1`, `blocked:owner-input` · Milestone: v0.3 (renamed from "Kandji sandbox validation")

Status: **blocked on owner**, who plans to request Iru (formerly Kandji) sandbox access through the vendor. No tenant exists yet; nothing here has been validated. Relates to WORK-006.

## WORK-012 — GitHub Pages site and branded README

Tracking: https://github.com/jsbonsai/minimodeLL/issues/13 · `area:site`, `type:docs`, `priority:p1` · Milestone: v0.2 (renamed from "GitHub Pages site and branded README")

**Status: done.** [PR #16](https://github.com/jsbonsai/minimodeLL/pull/16) merged the branded README and the `site/` static-site generator; the `GitHub Pages` deploy workflow run for the merge to `main` succeeded ([run 35945059549](https://github.com/jsbonsai/minimodeLL/actions/runs/35945059549)), and `curl -sI https://jsbonsai.github.io/minimodeLL/` returned `200` at integration time. The repository homepage is now set to that URL. Remaining, optional: upload the social preview image (owner-only, Settings UI) and a real sanitized app screenshot in the hero once the UI stabilizes.

## WORK-013 — MCP governance: stdio servers, user-added server controls, and an MCP access-request flow

Tracking: https://github.com/jsbonsai/minimodeLL/issues/15 · `area:mcp`, `area:policy`, `priority:p3` · No milestone (explicitly late backlog)

Status: open, owner idea captured 2026-09-23, not P1, nothing implemented. Covers stdio MCP servers as child processes (needs its own ADR: sandbox/helper design, pinned command/package identity, Keychain secret handling), managed capability switches (`allowUserStdioServers`, `allowUserHTTPServers`, allowed-host/package allowlists — enforced in `LocalAgentCore`, never delegated to the UI), and a "request an MCP server" approval flow.

## WORK-014 — Tool context control: per-task tool scoping, deferred tool loading, tool proxy

Tracking: https://github.com/jsbonsai/minimodeLL/issues/17 · `area:mcp`, `priority:p3` · No milestone (explore later, not P1)

Status: open, future exploration. Addresses `docs/project-state.md` limitation 15 (one configured tool set per run counts fully against the context budget before inference). Options to explore: per-task tool scoping, deferred tool loading (a meta-tool that lists/loads schemas on demand), or a core-side tool proxy that simplifies schemas and post-processes results — any of which must still enforce the allowlist in code and never widen permissions.

## WORK-015 — MDM adoption kit: least-friction Jamf and Iru deployment

Tracking: https://github.com/jsbonsai/minimodeLL/issues/18 · `area:mdm`, `area:packaging`, `priority:p2` · Milestone: v0.3

Status: open, owner request 2026-09-23, future-work checklist, nothing implemented. Developer ID signed/notarized/stapled PKG, Jamf Patch Management / Installomator + Iru Auto App metadata, silent install/upgrade/uninstall scripts, optional pre-provisioned read-only model/runtime PKG, JSON Schema preference manifests for both MDMs, and unified-logging documentation.

## WORK-016 — LAN / remote OpenAI-compatible inference servers (LM Studio, Ollama)

Tracking: https://github.com/jsbonsai/minimodeLL/issues/21 · `area:runtime`, `area:policy`, `priority:p1` · Milestone: v0.2

**Status: implemented (PR #24 merged); live validation against LM Studio on the owner's M2 Max pending.** Follow-ups: Settings "Test connection" button, approval-sheet destination line, optional address pinning to close the DNS-rebinding window, `.home.arpa` support if needed. Original request 2026-09-23: let a small laptop offload inference to an OpenAI-compatible server on the local network (LM Studio, Ollama, or `llama-server` on the owner's M2 Max, to be provided later). Proposed: a new `lan` provider kind restricted to RFC 1918/link-local/`.local` hosts, HTTPS preferred with plain HTTP only behind an explicit `allowInsecureTransport: true`, managed policy able to forbid it entirely, clear UI labeling of the destination before submission, and no automatic fallback between providers. Needs its own ADR.

## WORK-017 — MCP server management in Settings: CRUD, custom headers, auth modes

Tracking: https://github.com/jsbonsai/minimodeLL/issues/22 · `area:mcp`, `area:ui`, `priority:p1` · Milestone: v0.2

**Status: implemented (PR #27 merged); live MCP interoperability pending the owner's server.** Follow-ups: sandboxed `--probe-mcp` CLI, OAuth sign-out, GET/SSE header test, `allowUserHTTPServers` (WORK-013). Roll the app out before policies use `enabled`/`headers`: older builds ignore those keys. Original request 2026-09-23: full create/read/update/delete for HTTPS MCP servers in Settings instead of raw JSON — per-server tool allowlist and `requiresConfirmation`, auth mode (none/bearer/native OAuth), custom HTTP headers (secret values in Keychain, protocol-critical headers forbidden), a "test connection" flow, and forced-policy servers shown locked/read-only. Complements WORK-010 (the first live server) and WORK-013 (future governance switches).

---

Owner steering as of this integration (see `docs/handoff.md` for the full checkpoint): a Raycast-style design sprint (WORK-009) is running now, before further real-service testing; a live MCP server URL and the M2 Max LAN LM Studio setup (feeding WORK-010/WORK-016) will follow later; the Jamf sandbox path (WORK-006/WORK-011) goes through a coworker, and the Iru path through vendor outreach. The GitHub Project board is not yet created — it needs `gh auth refresh -s project,read:project` run by the owner (an agent token cannot grant itself that scope); see `docs/handoff.md`.

## WORK-018 — Shareable runtime profiles through Jamf/Iru

Tracking: https://github.com/jsbonsai/minimodeLL/issues/25 · `area:runtime`, `area:mdm`, `area:policy`, `priority:p2` · Milestone: v0.3

Status: future work, design first. Turn a power user's tuned llama-server settings into a typed, range-validated runtime profile (never raw command strings), importable from a pasted command with accepted/rejected flags explained, exportable for Jamf/Iru admins to scope to a department, and recorded in audit provenance. A policy capability (`allowCustomRuntimeProfiles`) gates who may author profiles.

## WORK-019 — Admin console / policy builder exploration

Tracking: https://github.com/jsbonsai/minimodeLL/issues/26 · `area:policy`, `area:mdm`, `priority:p3` · Milestone: v0.4

Status: exploration only. Cheapest first: a client-side policy builder on the Pages site and a Jamf JSON Schema manifest (WORK-015), before any hosted console.

