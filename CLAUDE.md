# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Read `AGENTS.md` first.** It is the authoritative agent contract for this repo: the handoff reading order (`docs/handoff.md` → `docs/project-state.md` → `docs/decisions/` → `docs/backlog.md`), product boundaries, security rules, the documentation that must be updated in the same commit as behavior changes, and GitHub authorization. This file only adds commands and a quick architectural orientation; it does not replace AGENTS.md.

## Commands

Requires Apple Silicon, macOS 14+, Xcode 16.4 / Swift 6.1+. CI (`.github/workflows/ci.yml`) runs on `macos-15` with Xcode 16.4.

```sh
swift test                                   # all tests (Swift Testing)
swift test --filter deniedActionNeverExecutes  # single test; tests are free @Test functions, filter by function name
swift test --filter RunnerTests              # one file's tests

swift run minimodell                         # UI dev run — NOT sandboxed
scripts/package-app.sh                       # builds build/minimodeLL.app (debug, ad-hoc signed, sandboxed)
open build/minimodeLL.app
codesign --verify --strict build/minimodeLL.app

swift run minimodell-diagnostics --config Config/local.example.json
swift run minimodell-diagnostics --config Config/enterprise.example.json
scripts/make-profile.py Config/enterprise.example.json build/minimodell.mobileconfig && plutil -lint build/minimodell.mobileconfig
scripts/mdm-readiness.sh build/minimodeLL.app Config/enterprise.example.json

python3 scripts/mock-inference.py            # canned fixture on 127.0.0.1:9931 for UI checks; not a model
```

Notes:
- The XCTest wrapper may print "Executed 0 tests" before Swift Testing runs; read the final Swift Testing summary.
- `CONFIGURATION=release` and `SIGNING_IDENTITY` (default `-`, ad-hoc) apply to packaging scripts; `INSTALLER_SIGNING_IDENTITY` is PKG-only. Scripts do not notarize.
- SwiftPM runs and the packaged `.app` use different Application Support directories, so configuration can look different between them. Sandbox, Keychain, and preferences behavior is only meaningful in the packaged app. Quit the menu bar app before rebuilding.
- No linter/formatter is configured.

## Validation expectations (from AGENTS.md)

Core execution/security changes → `swift test`. Configuration schema changes → diagnostics on both `Config/*.example.json`. Packaging changes → `scripts/package-app.sh` + strict codesign verify. UI/lifecycle changes → packaged app launch. Record new evidence in `docs/validation-results.md`; never claim a check passed unless it actually ran.

## Architecture

Three SwiftPM targets plus tests (`Package.swift`), with one pinned dependency: the official MCP Swift SDK at exactly 0.12.1.

- **`LocalAgentCore`** (library) — all policy, orchestration, provider, credential, and audit logic. Security boundaries live here and must be enforced in code (not via prompts or MCP annotations).
- **`MinimodeLL`** (executable `minimodell`) — SwiftUI menu bar app, settings, approval UI, and `ASWebAuthenticationSession` browser OAuth. Presentation only.
- **`AgentDiagnostics`** (executable `minimodell-diagnostics`) — offline config validator sharing core validation; no network, exits nonzero on failure. Used by MDM scripts.
- Jamf/Kandji integration lives only in `scripts/` and `docs/`; there is no MDM API dependency.

### Request flow

`AppState` (UI) re-resolves policy at every submission → `TaskRunner` captures one immutable policy snapshot for the run → loop: context-budget check (UTF-8 byte estimate of messages + tool schemas + output reservation) → `InferenceClient.complete` → at most one tool call per model response, validated (known tool ID/name, `ToolSchema` subset check, allowlist, approval requirement) → UI approval wait if `requiresConfirmation` → `ToolClient` executes via `MCPConnections` → result truncated to budget → repeat until final answer or limits (input bytes, output tokens, tool calls, result bytes, wall time). Every step writes an `Audit` event; audit write failure halts the task. Writes are never retried automatically.

`InferenceClient` and `ToolClient` are protocols so `RunnerTests` can use `FakeInference`/`FakeTools` with no model, server, or account — they are test seams, not a plugin system.

### Policy resolution (`Configuration.swift`)

Order: forced `PolicyJSON` in the `org.minimodell.agent` managed preference domain → user `config.json` in Application Support → bundled defaults. Forced managed policy is a **complete replacement**; user settings can never extend its model/tool allowlists; invalid forced policy **fails closed** (throws, blocks requests — no fallback). Local providers must be literal loopback HTTP; remote providers must be HTTPS; URLs may not contain credentials, query strings, or fragments; inference redirects are refused. There is no automatic cloud fallback, ever.

Adding a configuration field means updating the Codable type, validation, both example configs where relevant, `docs/configuration-reference.md`, and considering managed-policy behavior/migration.

### Other cross-cutting constraints

- **Branding/identity** is centralized in `Sources/LocalAgentCore/Resources/Branding.json` (read by `Brand.swift`). Don't hardcode the product name. `bundleIdentifier` anchors managed prefs, the OAuth callback (`org.minimodell.agent://oauth-callback`), storage, and Keychain records — treat it as stable. Visual assets: `Sources/MinimodeLL/Resources/BrandAssets/`, synced by `scripts/sync-brand-assets.py` (see `docs/branding.md`).
- **Tool schemas**: `ToolSchema.swift` supports only a JSON Schema subset; unsupported keywords (`$ref`, `oneOf`, `format`, `pattern`, …) reject the tool rather than being ignored.
- **Credentials**: Keychain only (`Credentials.swift`), including the MCP SDK `TokenStorage` adapter; OAuth storage is bound to endpoint + client ID hash. No client secrets for native OAuth.
- **Audit/logging**: JSONL + OSLog contain metadata only (timestamp, run ID, event, model/server/tool IDs). Never log prompts, responses, tool args/results, tokens, or raw remote error bodies.
- **Packaging**: don't put SwiftPM resource bundles at the `.app` root (breaks sealing); branding goes in `Contents/Resources`. Entitlements are in `packaging/App.entitlements`.
- No models or inference binaries are committed. The app talks to an externally started `llama-server` (`local` provider, alias `local-model`, port 9931), an HTTPS LiteLLM gateway, or — in a packaged build made after `scripts/fetch-runtime.sh` — its own bundled, pinned `llama-server` (`managed` provider; ADR 0008, `Runtime.swift`, `minimodell --runtime-smoke-test`). Managed providers should reference a verified catalog artifact (`runtime.artifact`; ADR 0009, `ModelCatalog.swift`, `ModelStore.swift`, Settings → Models, `minimodell --model-download`); files are size+SHA-256 verified before use.

`prd.md` / `prd-addendum.md` are historical; `docs/decisions/` ADRs supersede them. `docs/code-map.md` has a per-file responsibility table.
