# Current project state

Last reviewed: 2026-09-24 (coordinator integration of PRs #9, #14, #16, #19, #20). Stage: **0.1.0 developer preview**. No production release has been published.

## Product and owner intent

The owner administers an existing LibreChat deployment and its MCP integrations. API inference spending motivates moving routine, small workplace tasks onto employee Macs. The intended product is open source, useful to other enterprises, and substantial enough to demonstrate native app development, local inference, protocol integration, policy, auditability, and deployment engineering. Tagline as of this checkpoint: "Local models. MCP tools. Managed by IT."

The app name is minimodeLL. It must remain easy to rename. The standalone app comes first; optional Jamf and Iru (formerly Kandji) deployment/policy sit on top. Jamf is the initial live validation target, using the owner/coworker sandbox; Iru is best-effort with no test environment, pending vendor sandbox access. Explicit LiteLLM support remains valuable for approved cloud models, and a LAN/remote OpenAI-compatible provider (LM Studio, Ollama, or `llama-server` on another Mac) is now planned work (WORK-016) rather than only LiteLLM. The baseline tools are Gmail, Google Calendar, Atlassian and Slack; Salesforce, Asana and GitHub are later candidates. No live company endpoint, OAuth registration, or credential has been provided in this repository.

## Capability matrix

| Area | Implemented now | Evidence | Gap before production |
| --- | --- | --- | --- |
| Native app | SwiftUI window, menu bar, settings, result display, stop control | Packaged launch and UI inspection | Accessibility, sleep/wake, lifecycle and multi-window tests |
| Branding | Central identity JSON plus supplied app/menu icons, Twin L mark, adaptive palette and Geist fonts | Packaged branded workspace inspected after restart | Light/status variants need visual coverage; identity migration if forks rename deployed IDs |
| Bundled runtime | App-owned `managed` provider: `RuntimeManager` launches a pinned, embedded `llama-server` inheriting the app's sandbox, on a random loopback port with a per-launch key, authenticated readiness, idle unload, and a `minimodell-runtime-guard` helper that stops it if the app dies or is killed | Live sandboxed smoke test (`--runtime-smoke-test`) with a 135M model; hosted CI packages and verifies the embedded runtime's nested signatures (ADR 0008, PR #19) | Only proven with a tiny smoke-test model; no memory-pressure admission/unload; hung-inference cancellation unmeasured; Developer ID + hardened runtime path unverified |
| Model catalog | `ModelCatalog`/`ModelArtifact` manifest (source, size, SHA-256, license, template identity) validated against policy; `ModelStore` actor for resumable HTTPS download, disk-space check, verify-before-promote, cancel/delete/import; Settings → Models tab | Live sandboxed download + smoke test of the built-in artifact **Qwen3-4B-Instruct-2507 Q4_K_M** (Apache-2.0) on one M1 Pro/32 GB: ~1 s warm load, ~41 tok/s generation, peak RSS ~3.7 GB, synthetic tool round trip 3/3 (ADR 0009, PR #20) | Single-machine, single-model evidence, not a support claim; no shared/managed read-only artifacts, rollback, or signed catalog; Models tab/Import not visually verified |
| Local inference (external server) | Chat Completions requests to a configured literal loopback address (`local` provider, unmanaged) | Labeled synthetic HTTP fixture from sandboxed UI | Real model/tool-template qualification against a non-bundled server |
| LiteLLM | Explicit HTTPS provider and gateway model alias | Compiles; config validator exercised | Live gateway authentication, payload compatibility and model tests |
| MCP | Official SDK 0.12.1, Streamable HTTP, approved-tool discovery/execution | Compiles; runner tests use fake tools | **No live MCP server connected yet** (WORK-010, blocked on owner endpoint); actual four-service compatibility and malicious/slow transport tests |
| OAuth | Native browser delegate, SDK PKCE/discovery/refresh, Keychain token adapter | Compiles | **No live OAuth registration/callback exercised**; refresh/logout and trust-boundary validation |
| Credentials | Keychain generic passwords, no synchronization requested | Code/build review | Stable Developer ID signing and persistence failure UX |
| Policy | Versioned Codable JSON; forced MDM policy replaces user config; `managed` provider kind and catalog validation added | Validator tests and generated profile lint | Actual enrolled-device forced preference behavior |
| Execution safeguards | Input/context/output/step/result/time limits; tool schemas and approvals | Policy/runner/audit tests, extended for runtime and model-store behavior (56 `@Test` functions in the repository as of this review; see hosted CI runs cited in `docs/sessions/2026-09-23-runtime.md` and `-model-catalog.md` for pass evidence — not re-run in this documentation-only pass) | Exact token counting, transport memory limits, pressure-aware admission |
| Audit | Metadata JSONL and OSLog, bounded local retention | Payload-shape and write-failure tests; fixture run | Richer provenance/outcome events and optional central export |
| Diagnostics | CLI policy validation, RAM/OS, eligible model IDs, model-catalog check | Three examples (local, enterprise, bundled-runtime) pass on development Mac | Connectivity or performance qualification runner |
| Packaging | Ad-hoc sandboxed .app (with or without the bundled runtime embedded); DMG/PKG scripts | .app signature and launch verified with and without the runtime | DMG/PKG install, **Developer ID and notarization still not done**, clean-machine checks |
| Site | GitHub Pages landing/documentation site (`site/`) generated from repository Markdown, deployed by `.github/workflows/pages.yml` | **Live**: `https://jsbonsai.github.io/minimodeLL/` returns 200; the deploy workflow run for the `main` merge succeeded; repository homepage now set to that URL | Social preview image not uploaded (owner-only UI action); no live-app screenshot in the hero yet |
| Open source | Public GitHub repo, MIT, contributor/security docs, CI, 22 tracked issues (WORK-001–WORK-017) across `v0.2`/`v0.3`/`v0.4` milestones with area/type/priority labels | Foundation and follow-up commits pushed; hosted CI green on `main` after every merge today (see `docs/sessions/2026-09-23-coordinator.md`) | Production release practices, GitHub Project board (blocked on `gh auth refresh -s project,read:project`) pending |

## Actual local checkpoint

- Repository started with two PRDs and no implementation or Git history.
- A fresh Swift package now contains three products: reusable core, app, diagnostics.
- Initial development `.app` is generated at `build/minimodeLL.app`; it is ignored by Git. A release build with the bundled runtime embedded is produced the same way with `REQUIRE_RUNTIME=1 scripts/package-app.sh` after `scripts/fetch-runtime.sh`.
- The project does not ship a runtime or GGUF in the repository, but a packaged build can now fetch a pinned, verified llama.cpp binary (`vendor/`, gitignored) and download a verified, approved model into the app's own sandbox container (also outside the repository). One real model (Qwen3-4B-Instruct-2507 Q4_K_M) has been benchmarked, on one development Mac only; see the capability matrix above and `docs/validation-results.md`.
- Earlier sessions left the SmolLM2-135M smoke-test model (~145 MB) and the Qwen3-4B model (~2.5 GB) in `~/Library/Containers/org.minimodell.agent/Data/Library/Application Support/org.minimodell.agent/Models/` on the development Mac used for those sessions. Do not delete them without checking whether the next agent needs them; they are not tracked in Git either way.
- The app may be open from a previous session. Inspect the local machine before restarting it; this is not a requirement for code work.
- User configuration/audit files created by the preview live outside the repository, in its sandbox container. Do not commit them.
- The GitHub Pages site (`site/`) is live at https://jsbonsai.github.io/minimodeLL/, which is also now the repository homepage. GitHub hosting/bootstrap status is tracked in `docs/handoff.md` and the latest session records.

## Known limitations and sharp edges

1. Local inference no longer strictly requires an external server: a packaged build with the bundled runtime embedded (`managed` provider) launches, authenticates, idle-unloads and terminates its own `llama-server`, with a supervisor helper for crash/kill cleanup. The `local` provider path (external, unmanaged `llama-server`) still exists unchanged and does not launch, unload, authenticate by default, or terminate that server; configured bearer authentication is available but optional there.
2. RAM eligibility checks total physical RAM only. They do not measure current availability, pressure, KV cache or swapping.
3. Context accounting is a conservative UTF-8-byte estimate of encoded messages and tools, plus output/framing allowance. It is not the model's tokenizer or rendered template.
4. MCP result limits apply after SDK buffering/decoding. Non-text or empty results fail rather than silently dropping content. Structured-content-only, image and resource responses are not supported.
5. Tool schema support is an explicit subset. Unsupported constraints reject discovery; a real company's schemas may therefore require compatibility work before first use.
6. OAuth token storage callbacks cannot throw through the SDK's `TokenStorage` protocol. Persistence failures currently emit a generic OSLog error, and load failures return no token. This needs explicit user-facing diagnosis and validation.
7. SDK cancellation and streaming behavior against unresponsive peers are not proven by fake-tool tests. TaskGroup deadlines rely on operations responding to cancellation/disconnect; they are not process-level hard deadlines.
8. App policy is sampled at task start. It does not retroactively stop an already accepted remote action when MDM policy changes.
9. The UI checks selected model ID and provider kind/URL after reloading policy, preventing an unnoticed destination switch on submission. It does not yet compare every model alias, credential, prompt, and tool policy field for a full policy revision review.
10. Configuration decoding ignores unknown JSON keys. The generator serializes policy but does not independently run Swift validation. Follow the documented validation-before-generation sequence.
11. Audit entries do not contain a policy hash, model artifact hash, latency, normalized failure code or explicit uncertain-write outcome. Local files are user-modifiable and not an immutable audit service.
12. The `local`/LiteLLM provider examples remain stubs; `minimumMemoryGB: 16` does not certify a model for a 16 GB machine and the alias `local-model` is not a chosen model. The bundled-runtime path now has one real, chosen, verified catalog artifact (Qwen3-4B-Instruct-2507 Q4_K_M), but only single-machine evidence backs its memory/context settings — see WORK-005.
13. The packaged sandbox and SwiftPM development execution use different Application Support locations. A successful `swift run` is not a sandbox test.
14. The current diagnostics reports `arm64` as a fixed target label. It is intended for the Apple Silicon scope and should use measured architecture if additional architectures are supported.
15. The schema exposes one configured tool set for a run, not yet task-specific tool selection or a model router. Large tool sets can exhaust the conservative context estimate before inference.

## Immediate next implementation

The pinned, authenticated, sandbox-compatible bundled llama.cpp lifecycle (WORK-001) and a first verified model artifact (WORK-002) are done as readiness/trimmed slices (see the capability matrix). Follow the ordered backlog for what remains: visually verifying Settings → Models and a GUI task with the managed Qwen artifact, then either hardening (WORK-003, WORK-005) or connecting a first live MCP server (WORK-010, blocked on the owner) and a LAN inference provider (WORK-016). A parallel design sprint (WORK-009, Raycast-style UI/UX) and MCP server CRUD (WORK-017) are running now per current owner steering — see `docs/handoff.md`.

## Website and repository presentation

The GitHub Pages landing/documentation site and branded README planned in [website-plan.md](website-plan.md) are implemented and deployed: [PR #16](https://github.com/jsbonsai/minimodeLL/pull/16) merged `site/` (a small Python static-site generator rendering repository Markdown) and the `.github/workflows/pages.yml` deploy workflow. The site is live at https://jsbonsai.github.io/minimodeLL/ (verified `200` and a successful deploy workflow run on the `main` merge), and the repository homepage is now set to that URL. The social preview image is not uploaded (Settings → General → Social preview is a UI-only, owner-side action). See `docs/sessions/2026-09-23-site-and-readme.md` and ADR [0010](decisions/0010-static-site-generation.md).
