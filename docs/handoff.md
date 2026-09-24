# Agent handoff — read this first

Last updated: 2026-09-23. Current checkpoint: supplied brand assets integrated and local app rebuilt/restarted on feat/brand-assets. See docs/branding.md and docs/sessions/2026-09-23-brand-assets.md. Next major implementation remains WORK-001 / issue #1.

## Owner instructions that persist

The owner gave broad implementation responsibility for minimodeLL, wants a polished open-source macOS project, and explicitly authorized creating a GitHub repository plus ongoing commits/pushes through authenticated `gh`. The owner asks for thorough, continuous documentation so a replacement agent can resume after rate limits without needing chat history. Jamf and Kandji must remain optional deployment adapters. Jamf is the first live validation path: the owner has an environment and a coworker can provide a focused sandbox test. Kandji is best-effort because no tenant or sandbox is available. LiteLLM, approved model stubs, auditability, sandboxing, safeguards and customizability are intended features. Branding must be modular.

The owner's available fleet is M1 Pro 32 GB (development), M2 Max 64 GB, M1 Pro 16 GB and MacBook Air 24 GB. Only the development Mac has been used so far. Do not publish measurements for the others.

## Current checkpoint

The first implementation is a native developer preview. It includes app/UI, configuration/policy, provider/MCP adapters, Keychain/OAuth wiring, bounded tool loop, local metadata audit, tests, diagnostics and packaging scaffolding. It is **not yet self-contained**: no inference runtime or model is bundled. No company integration is configured or live validated. Read `project-state.md` for the complete capability/limitation matrix.

The implementation was locally validated with 16 tests and an explicitly labeled mock HTTP response from the sandboxed app. There is no real model benchmark, live LiteLLM/MCP/OAuth evidence, or real Jamf enrollment evidence. DMG/PKG scripts exist but production signing/notarization/installation is pending.

Public repository: https://github.com/jsbonsai/minimodeLL. Foundation commit `283ad43` was pushed to `main`, with `origin` tracking the GitHub repository. Issues #1–#8 track WORK-001 through WORK-008. Initial CI run https://github.com/jsbonsai/minimodeLL/actions/runs/35936009136 failed because fake inference inherited the real starter model RAM requirement. Commit `3689e10` fixes the fixture and adds a dedicated memory admission regression test. Corrected run: https://github.com/jsbonsai/minimodeLL/actions/runs/35936172136 **passed** for commit `3689e10`, including 16 tests, both policy examples, app packaging, shared MDM readiness and profile lint. The final checkpoint commit changes Markdown documentation only; CI intentionally skips Markdown-only changes.

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

Start WORK-001: a pinned local inference runtime with authenticated, sandbox-compatible app-owned lifecycle. Produce a small working proof of the helper/process boundary before choosing/download-integrating a model. Update the ADR with measured findings and add failure-path tests. Follow with verified model artifact management (WORK-002). WORK-003 transport/cancellation hardening can also be tackled independently before any real-service pilot.

Do not start by adding a cloud fallback, document ingestion, unbounded chat history, or more hypothetical RAM tiers. These distract from the unproven core: running a qualified local model reliably and safely in the packaged app.

## Information and resources not yet available

- Actual MCP endpoints, transports, tool schemas, public native OAuth registrations and test accounts.
- Selected/pinned llama.cpp revision, approved GGUF, model/template hash and distribution license review.
- Developer ID signing/notarization access and the concrete Jamf sandbox scope/enrolled device. A Jamf environment is available in principle through the owner/coworker, but access and scope are not yet configured here. No Kandji environment exists for testing.
- Measured hardware performance or quality thresholds.

Useful local work can proceed without these. Ask for concrete details when they block the selected task; never ask for secrets to be committed or pasted into public issues.

## Local environment and artifacts

Original checkout: `~/dev/minimodel` (directory name is intentionally still the original working name). Swift 6.1.2, Xcode 16.4, macOS 15.7.7, Apple Silicon 32 GB. No llama-server binary was found during initial setup. Recheck rather than assuming the machine has not changed.

`build/minimodeLL.app` is a generated ad-hoc signed preview and is ignored by Git. The local fixture from initial UI validation was stopped. The app was reopened at the end of initial work and may still be running. Packaging creates no cloud deployment and no release. User configuration and audit data live in the app's sandbox container, outside the repository.

## Required handoff maintenance

Before stopping, update this document with the new active checkpoint, next action, blockers, relevant branch/PR/CI references, running local processes and uncommitted changes. Add a session record and update state/backlog/ADRs as needed. Avoid embedding the current commit's own hash in a file inside that commit; use Git history or reference the preceding checkpoint.

## End-of-session operational state

The documentation bootstrap was committed to origin/main. The subsequent branding update is on feat/brand-assets; inspect its PR/CI and branch before resuming. No new inference/mock servers or benchmark processes were started during the documentation session. The preview app may still be open from the earlier implementation session. There are no credentials or live service endpoints in the repository. Eight GitHub issues preserve the next work; begin with https://github.com/jsbonsai/minimodeLL/issues/1 unless the owner redirects priorities.

The latest local app uses the supplied Twin L app/menu icons, in-app logo, adaptive palette and Geist fonts. It was restarted after the branding build and left open. This changes presentation/resources only; runtime/MCP limitations above still apply.
