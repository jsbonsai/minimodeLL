# Changelog

No production release has been published. Version 0.1.0 identifies the current developer preview.

## Unreleased

### Added

- Raycast-inspired command bar (WORK-009, PR #28): global ⌥Space floating panel with destination chip, inline tool approval (⌘↩/⌘⌫ with a 0.6 s arming window so keystrokes meant for another app can't approve), ⌘K actions, design tokens, Reduce Motion/Transparency fallbacks, preview renderer (`--render-design-previews`).
- `lan` inference provider kind (ADR 0011, WORK-016, PR #24): OpenAI-compatible servers on private IPv4/IPv6 addresses or `.local` names (LM Studio, Ollama, llama-server). HTTPS, or plain HTTP only with `allowInsecureTransport: true`; `.local` names are re-resolved and checked before every request; the destination label shows `LAN · TLS` or `LAN · unencrypted` before submission; connection test via `minimodell-diagnostics --probe-provider <id>` / `minimodell --probe-provider <id>`; optional Keychain bearer token; example `Config/lan-lmstudio.example.json`; Info.plist adds `NSLocalNetworkUsageDescription`.
- Settings → MCP Servers (ADR 0012, WORK-017, PR #27): add, edit, enable/disable, delete and test HTTPS MCP servers; per-server auth mode (none, bearer, OAuth), custom request headers with secret values in Keychain and reserved protocol headers rejected, tool approval chosen from discovered tools. Servers from forced managed policy are read-only. New optional `enabled` and `headers` keys.
- App-owned bundled llama.cpp runtime (`managed` provider): pinned official `ggml-org/llama.cpp` prebuilt fetched and verified by `scripts/fetch-runtime.sh`, embedded in the packaged app, launched and supervised by `RuntimeManager` with a `minimodell-runtime-guard` helper (orphan cleanup on app termination), random loopback port, per-launch key, authenticated readiness, and idle unload. Adds the `network.server` entitlement for loopback listening and a `--runtime-smoke-test` CLI mode. Proven live only with a 135M smoke-test model, not yet a qualified model (WORK-001, partial; PR #19).
- Verified model artifact catalog and download manager: `ModelCatalog`/`ModelArtifact` (source, size, SHA-256, license, template identity, runtime tag), `ModelStore` with resumable HTTPS download, disk-space checks, verify-before-promote, cancel/delete/import, and a Settings → Models tab (`--model-download` CLI mode). Ships with one built-in, approved artifact, **Qwen3-4B-Instruct-2507 Q4_K_M** (Apache-2.0), run live in the sandboxed bundled runtime on one development Mac (about 1 s warm load, about 41 tok/s generation, peak RSS about 3.7 GB, synthetic tool round trip 3/3 — single-machine evidence, not a support claim) (WORK-002, partial; PR #20).
- Branded README and a GitHub Pages documentation/landing site (`site/`), generated at build time from repository Markdown via `site/build.py` and deployed by `.github/workflows/pages.yml`; live at https://jsbonsai.github.io/minimodeLL/, now set as the repository homepage (PR #16).
- GitHub project organization: area/type/priority labels, `v0.2`/`v0.3`/`v0.4` milestones, and issue triage across WORK-001 through WORK-017 (PR #14 plus coordinator follow-up).
- Renamed "Kandji" to "Iru (formerly Kandji)" throughout agent-facing and product documentation, reflecting the vendor's rebrand (PR #14). The optional, best-effort deployment target itself is unchanged; only the name and doc wording changed.
- Supplied Twin L app and menu bar icons, adaptive brand palette, Geist typography and in-app branding; reproducible resource synchronization.

- Native macOS SwiftUI task window, menu bar, settings, credential entry and tool approval review.
- Shared Swift core with local/LiteLLM adapters, official MCP SDK integration and native OAuth/Keychain wiring.
- Versioned approved model/provider/tool policy with optional complete forced MDM override.
- Bounded task execution, explicit schema/tool checks, conservative context estimates and metadata audit.
- Policy/hardware diagnostics, Jamf profile generation and hardware inventory example.
- Sandboxed app packaging, DMG/PKG build scaffolding, dependency notices and centralized branding.
- Deterministic core tests, a labeled local UI fixture, CI definition and validation records.
- Shared MDM readiness checks, focused Jamf sandbox plan and best-effort Kandji deployment documentation.
- MIT licensing, contributor/security guidance, detailed ADRs, configuration reference, code map, backlog, session history and agent handoff protocol.

### Limitations

- Local inference no longer strictly requires an external llama-server: a packaged build made after `scripts/fetch-runtime.sh` can own a bundled runtime and one built-in model. That path is proven only on one development Mac with one small model; the external-server (`local`) and LiteLLM paths remain available and unchanged.
- No live MCP server, native OAuth flow, or enrolled Jamf/Iru device has been exercised; these remain blocked on owner-provided endpoints/credentials and sandbox access (WORK-004, WORK-010, WORK-006, WORK-011).
- Developer ID signing, notarization, and DMG/PKG install with the bundled runtime are not done (WORK-006, WORK-015).
- Transport hardening, exact token counting, and fleet hardware benchmarks remain open work (WORK-003, WORK-005).

### Fixed

- macOS smart dashes/quotes no longer corrupt API keys, headers or JSON typed into the app; typographic characters in header values get a specific error (PR #30).
- Fake-inference unit fixtures no longer assume a 16 GB CI machine; a dedicated test covers physical-memory admission separately.
