# Agent handoff — read this first

> **Paused 2026-09-23 for a macOS upgrade.** Read [checkpoints/2026-09-23-macos-26-upgrade.md](checkpoints/2026-09-23-macos-26-upgrade.md) first: the owner is moving the dev Mac to macOS Tahoe 26.7 + Xcode 26 so the next sprint can implement Liquid Glass across the whole app (WORK-020, #31). WORK-009 command bar (#28) and the smart-dash fix (#30) are merged.

Last updated: 2026-09-24. Current checkpoint: five parallel streams merged to `main` today and were integrated by a coordinator pass — see `docs/sessions/2026-09-23-coordinator.md` for the full merge/review/issue-triage record. `main` now has: Twin L branding (PR #9), a GitHub org/label/milestone cleanup and the Kandji→Iru rename (PR #14), a branded README and a **live** GitHub Pages site (PR #16, now the repository homepage), an app-owned bundled llama.cpp runtime readiness slice (PR #19, WORK-001 partial), and a verified model catalog with the first real model running in that runtime, Qwen3-4B-Instruct-2507 Q4_K_M (PR #20, WORK-002 partial). Read `docs/project-state.md` for the current capability matrix and `docs/backlog.md` for the full WORK-001–WORK-017 status. Two sprint-2 work streams (Raycast-style UI redesign WORK-009/#10, MCP server CRUD WORK-017/#22) and a LAN-inference stream (WORK-016/#21) are running in parallel with this integration.

## Owner instructions that persist

The owner gave broad implementation responsibility for minimodeLL, wants a polished open-source macOS project, and explicitly authorized creating a GitHub repository plus ongoing commits/pushes through authenticated `gh`. The owner asks for thorough, continuous documentation so a replacement agent can resume after rate limits without needing chat history. Jamf and Iru (formerly Kandji) must remain optional deployment adapters. Jamf is the first live validation path: the owner has an environment and a coworker can provide a focused sandbox test — this is arranged through that coworker, not directly by the owner. Iru is best-effort because no tenant or sandbox is available; the owner is pursuing sandbox access through vendor outreach (see WORK-011/#12). LiteLLM, approved model stubs, auditability, sandboxing, safeguards and customizability are intended features. Branding must be modular. Current tagline: "Local models. MCP tools. Managed by IT."

The owner's available fleet is M1 Pro 32 GB (development), M2 Max 64 GB, M1 Pro 16 GB and MacBook Air 24 GB. Only the development Mac has been used so far. Do not publish measurements for the others. The owner plans to provide a live MCP server URL and set up an M2 Max running LM Studio on the LAN later (feeding WORK-010 and WORK-016 respectively); neither has been provided as of this checkpoint.

**Owner is away as of this checkpoint.** Do not wait on owner input to make progress on unblocked work (see `docs/backlog.md` for what is and is not blocked); queue questions rather than pausing.

**Multi-agent caps** (owner instruction, relayed 2026-09-23, not yet enforced anywhere in code or process): a maximum of 8 parallel agents at once, and a maximum of 2 agents working against the same model tier/provider concurrently (to bound concurrent local-runtime/API load). No mechanism currently checks or enforces this; treat it as a coordination convention for whoever is orchestrating parallel streams until it is built into tooling, if ever.

**GitHub Project board still blocked**: the authenticated `gh` token lacks the `project`/`read:project` scopes needed for `gh project create`. The owner needs to run `gh auth refresh -s project,read:project` once, after which `gh project create --owner jsbonsai --title "minimodeLL roadmap"` (and `gh project item-add` for each issue) can proceed. No agent token can grant itself this scope.

**Steering priority for the current sprint**: a Raycast-style UI/UX redesign (WORK-009/#10) is prioritized as a design sprint *before* further real-service testing (i.e. before WORK-004's live MCP/OAuth qualification work). It is running now, in parallel with LAN inference (WORK-016/#21) and MCP server CRUD (WORK-017/#22); see `docs/backlog.md` for each item's current status.

## Current checkpoint

The implementation is a native developer preview that, as of today, can be **self-contained for one small model**: a packaged build made after `scripts/fetch-runtime.sh` embeds a pinned llama.cpp runtime, and that runtime can download, verify and run the built-in Qwen3-4B-Instruct-2507 Q4_K_M catalog artifact end to end (readiness slices of WORK-001/WORK-002; see `docs/project-state.md`'s capability matrix for exactly what is and is not proven). The external-server (`local`) and LiteLLM provider paths are unchanged. No company MCP/OAuth integration is configured or live validated yet, and no enrolled Jamf/Iru device or Developer ID signing exists.

Read `project-state.md` for the complete capability/limitation matrix — do not treat this paragraph as a substitute for it.

Public repository: https://github.com/jsbonsai/minimodeLL, now with its homepage set to the live Pages site https://jsbonsai.github.io/minimodeLL/. 22 issues (WORK-001 through WORK-017, some split from earlier #1–#8 numbering plus newly opened ones) track work across the `v0.2`/`v0.3`/`v0.4` milestones; see `docs/backlog.md` for the current status of each and `docs/sessions/2026-09-23-coordinator.md` for how today's five PRs (#9, #14, #16, #19, #20) were merged, two runtime/store bugs found and fixed before merging (#19, #20), and issues/labels/milestones triaged. Hosted CI is green on `main` after every merge today (see that session record for the specific run links); the historical CI failure/fix from the initial checkpoint (`283ad43` → `3689e10`, runs 35936009136 → 35936172136) remains accurate history and is not repeated here.

## Resume sequence

```sh
git status --short
git log -5 --oneline
git remote -v
gh issue list --state open
gh run list --limit 5
```

Then read `AGENTS.md`, `docs/project-state.md`, `docs/backlog.md`, `docs/decisions/README.md`, and the newest `docs/sessions/` record. If working in a fresh checkout, use `docs/development.md` to reproduce build/test/package steps. Preserve any uncommitted work and inspect an active failed CI run before beginning unrelated features.

## Recommended next implementation

WORK-001 and WORK-002 have readiness/trimmed slices merged (PRs #19, #20); do not restart them from scratch. Next: visually verify Settings → Models and a GUI-submitted task with the managed Qwen artifact (no UI automation has exercised this yet), then pick up either hardening work (WORK-003 transport/cancellation, WORK-005 exact context budgets) or unblocked feature work (WORK-016 LAN inference, WORK-017 MCP server CRUD, WORK-009 Raycast redesign — all explicitly running now per current owner steering above). WORK-004/WORK-010 (live MCP/OAuth) and WORK-006/WORK-011 (Jamf/Iru enrollment) remain blocked on the owner.

Do not start by adding a cloud fallback, document ingestion, unbounded chat history, or more hypothetical RAM tiers. These distract from the unproven core: running a qualified local model reliably and safely in the packaged app, at fleet scale (WORK-005) and with real services (WORK-004).

## Information and resources not yet available

- Actual MCP endpoint URL, auth mode and tool names for WORK-010 (owner will provide); an M2 Max running LM Studio on the LAN for WORK-016 (owner will set up); actual public native OAuth registrations and test accounts.
- Developer ID signing/notarization access and the concrete Jamf sandbox scope/enrolled device. A Jamf environment is available in principle through the owner/coworker, but access and scope are not yet configured here. No Iru (formerly Kandji) tenant exists for testing; the owner is pursuing vendor sandbox access.
- Measured hardware performance or quality thresholds across the fleet beyond the one M1 Pro/32 GB development Mac (WORK-005).
- `gh auth refresh -s project,read:project`, needed once from the owner before a GitHub Project board can be created.

Useful local work can proceed without these. Ask for concrete details when they block the selected task; never ask for secrets to be committed or pasted into public issues. The owner is away as of this checkpoint — queue these questions rather than blocking on them.

## Local environment and artifacts

Original checkout: `~/dev/minimodel` (directory name is intentionally still the original working name). Swift 6.1.2, Xcode 16.4, macOS 15.7.7, Apple Silicon 32 GB. `scripts/fetch-runtime.sh` now vendors a pinned llama.cpp binary into gitignored `vendor/`; recheck local state rather than assuming the machine has not changed.

`build/minimodeLL.app` is a generated ad-hoc signed preview and is ignored by Git (a release variant with the runtime embedded is built the same way; see CLAUDE.md commands). Packaging creates no cloud deployment and no release. User configuration and audit data live in the app's sandbox container, outside the repository. **Models left in that container from today's sessions, on the development Mac used for them**: `Qwen_Qwen3-4B-Instruct-2507-Q4_K_M.gguf` (~2.5 GB, verified, the catalog's built-in artifact) and `SmolLM2-135M-Instruct-Q8_0.gguf` (~135 MB, smoke-test only, not a catalog artifact) under `~/Library/Containers/org.minimodell.agent/Data/Library/Application Support/org.minimodell.agent/Models/`. Do not delete either without a reason; the next agent testing the runtime or model store can reuse them instead of re-downloading. If you edit that container's `config.json` for a live test, back it up first and restore it byte-for-byte afterward (every session so far has done this correctly).

## Required handoff maintenance

Before stopping, update this document with the new active checkpoint, next action, blockers, relevant branch/PR/CI references, running local processes and uncommitted changes. Add a session record and update state/backlog/ADRs as needed. Avoid embedding the current commit's own hash in a file inside that commit; use Git history or reference the preceding checkpoint.

## End-of-session operational state

All five of today's PRs (#9, #14, #16, #19, #20) are merged to `main`; no PR is open, and no branch was force-pushed. This documentation-integration pass (`docs/integrate-v02`) made no source, config, or packaging changes — only `docs/handoff.md`, `docs/project-state.md`, `docs/backlog.md`, `CHANGELOG.md`, `docs/sessions/README.md`, `docs/roadmap.md` and the new `docs/sessions/2026-09-23-coordinator.md` were touched — so `swift test`/packaging/diagnostics were not re-run here; see `docs/sessions/2026-09-23-coordinator.md` for what was actually checked (hosted CI status, live Pages check, `gh` metadata) and each feature stream's own session record for the code-level validation. Per each stream's own session record, nothing was left running on the development Mac (`minimodell`, `minimodell-runtime-guard`, `llama-server` all confirmed stopped) and each stream's edits to the app container's `config.json` were restored byte-for-byte. Two models remain in that container's `Models/` folder (see "Local environment and artifacts" above) — left intentionally, not an oversight.

GitHub state: repository homepage set to https://jsbonsai.github.io/minimodeLL/ (verified live) by this integration pass; 22 open issues across three milestones; labels applied; GitHub Project board still blocked on the owner running `gh auth refresh -s project,read:project`. Begin further work from `docs/backlog.md`'s ordering unless the owner redirects priorities; the previously recommended starting point (WORK-001/#1) now has a merged readiness slice, so pick up its remaining items or move to the next unblocked item instead of restarting it.

## Latest owner steering (2026-09-23, relayed for today's parallel streams)

Tagline: "Local models. MCP tools. Managed by IT." The owner is away as of this checkpoint; do not block unblocked work waiting for a reply, queue questions instead. A live MCP server URL (for WORK-010/#11) and an M2 Max set up with LM Studio on the LAN (for WORK-016/#21) are both coming later — neither has been provided yet. A Raycast-inspired design sprint (WORK-009/#10, moved into the v0.2 milestone) is prioritized *before* further real-service testing. The Jamf sandbox path continues through the owner's coworker (WORK-006/#6); the Iru (formerly Kandji) sandbox path continues through vendor outreach (WORK-011/#12) — neither is available yet. Multi-agent coordination caps relayed by the owner: a maximum of 8 agents running in parallel, and a maximum of 2 agents against the same model tier/provider at once; nothing currently enforces this automatically. The GitHub Project board needs the owner to run `gh auth refresh -s project,read:project` once before `gh project create` will work. Sprint 2 — LAN inference (WORK-016/#21), MCP server CRUD (WORK-017/#22), and the Raycast redesign (WORK-009/#10) — is running in parallel with this documentation-integration pass; check each one's own branch/PR/session record before assuming its status, since this file is a snapshot at integration time, not a live view.

The previous "website plan only" checkpoint (below, for history) has since been fully implemented and deployed; see the "Current checkpoint" section above and `docs/sessions/2026-09-23-site-and-readme.md`.

### Historical: document the website plan only (superseded 2026-09-23/24)

The owner asked for GitHub README/documentation branding and a GitHub-hosted landing/documentation site, then explicitly requested only a documented plan before another agent takes over. [Website plan](website-plan.md) contains the full proposed content, asset paths, architecture, publication options, dependency on unmerged PR #9, and exact resume steps. [Session record](sessions/2026-09-23-website-plan.md) records the actual discovery. This checkpoint is preserved for history; the site described in it is now built and live (see above), so do not treat "plan only" as the current state.

## Sprint 2 merged (2026-09-23, coordinator)

- PR #23 docs integration, PR #24 LAN inference (WORK-016) and PR #27 MCP server management (WORK-017) are merged to `main`. Both passed independent review; one reviewer suggestion (save Keychain secrets after the config write) was deliberately not applied because the reverse order can leave config pointing at a missing secret, while the current order leaves at worst an inert Keychain item (documented in ADR 0012).
- PR #28 Raycast-inspired command bar (WORK-009) had five major review findings (approval could be triggered by a ⌘↩ typed in another app, dark-mode button contrast, warning-pill contrast, workspace opener not wired at launch, stale hotkey status). A follow-up agent is fixing them on `feat/raycast-design`; do not merge #28 until those fixes and CI are green.
- New backlog captured from the owner: WORK-018 shareable runtime profiles through Jamf/Iru (#25) and WORK-019 admin console / policy builder exploration (#26).
- **Owner live checks now unblock the most value:** LM Studio on the M2 Max (steps in `sessions/2026-09-23-lan-inference.md`, Remaining work 1) and the production Streamable HTTP MCP server (Settings → MCP Servers → Add server → Test connection).
