# Code map and change entry points

## Build and package

- `Package.swift`: Swift 6.1 package, macOS 14 minimum, library/app/CLI/test targets, exact MCP SDK 0.12.1 dependency, branding resource.
- `Package.resolved`: transitive dependency lock. Commit intentional resolution changes and explain them. Some resolved dependencies are for SDK targets that this app does not compile; do not assume every resolved package is shipped.
- `packaging/App.entitlements`: App Sandbox, outbound network, loopback listening (`network.server`, required by the inheriting runtime helper), user-selected read-only file access.
- `packaging/Helper.entitlements`: exactly `app-sandbox` + `inherit` for `llama-server` and the runtime guard.
- `packaging/runtime.lock.json`: pinned llama.cpp release (tag, commit, asset URL, size, SHA-256, license, expected dylib closure).
- `scripts/fetch-runtime.sh`: downloads the pinned asset, verifies size/SHA-256 before extraction, checks closure/arch/license, vendors into gitignored `vendor/llama.cpp/<tag>/`. `RUNTIME_LOCK` overrides the lock for negative tests.
- `scripts/package-app.sh`: builds SwiftPM products, creates Info.plist, copies branding/licenses, embeds the fetched runtime when present (`Contents/Helpers`, `Contents/Frameworks`, rpath rewrite, llama.cpp license, lock copy), signs nested code inside-out, then CLI and app, and runs `codesign --verify --strict --deep`. `REQUIRE_RUNTIME=1` fails if the runtime was not fetched. Defaults to debug and ad-hoc signing.
- `scripts/package-dmg.sh`: release build and drag-to-Applications image; optional application-certificate signing.
- `scripts/package-pkg.sh`: release build and `/Applications` component package; optional installer-certificate signing.
- `.github/workflows/ci.yml`: macOS test, example policy validation (four examples), app packaging without and with the fetched runtime plus nested-signature/entitlement checks, profile generation/lint. Hosted execution must be checked, not inferred from local success.

## Core (`Sources/LocalAgentCore`)

| File | Responsibility | Important boundary |
| --- | --- | --- |
| `Brand.swift` | Reads branding, stable identity, support directory | Packaged app/CLI resource lookup precedes SwiftPM fallback |
| `Resources/Branding.json` | Display name, version, bundle identity | Identity changes affect policy, Keychain and callbacks |
| `Configuration.swift` | Codable schema, endpoint/ID/limit validation (`validateProviderEndpoint`, `validateLANEndpoint`), source precedence | Forced managed policy replaces user config; invalid forced policy throws; `allowInsecureTransport` only on `lan` + `http` |
| `Inference.swift` | Chat/tool DTOs, `InferenceClient`, compatible HTTP client, context estimate | Refuses redirects, caps HTTP response at 262,144 bytes, sends nonstreaming Chat Completions; re-validates the provider endpoint (`verifiedBaseURL`) before every request |
| `LANProvider.swift` | `LANHost` (private-address / `.local` classification, request-time resolution check), `InferenceDestination` labels, `ProviderSpec.verifiedBaseURL`, `ProviderProbe` (`GET /models` connection test) | Non-`.local` names and public/loopback addresses rejected; any public address in a `.local` answer refuses the request; probe returns model IDs only, 64 KiB cap (ADR 0011) |
| `MCPConnections.swift` | SDK client lifecycle, paginated discovery, aliases, allowlists, text results | At most 10 discovery pages; OAuth storage bound to endpoint and client ID hash |
| `Credentials.swift` | Keychain bearer storage and OAuth `TokenStorage` adapter | Tokens never enter configuration files; persistence failure behavior is limited |
| `ToolSchema.swift` | Supported schema subset and argument checks | Unsupported validation keywords fail closed |
| `TaskRunner.swift` | Input admission, model selection, model/tool loop, approvals, cancellation, audit | One call per model step, bounded calls, no automatic write retries |
| `Audit.swift` | Actor-owned JSONL rotation and OSLog metadata | No task content fields; write failure blocks progression |
| `Runtime.swift` | `RuntimeState`, `RuntimeEndpoint`, `RuntimeProcess`/`RuntimeHost` seams, `RuntimeManager` actor, `ManagedInferenceClient` | Per-launch key never logged/persisted; key-challenge readiness; leases gate idle unload; crash → `failed`, no auto restart or cloud fallback |
| `RuntimeHost.swift` | `SystemRuntimeHost`: loopback port reservation, `Process` launch with explicit env and discarded output, loopback-only bounded probes | Refuses non-loopback probe URLs and redirects |
| `RuntimeSmokeTest.swift` | End-to-end runtime check used by `minimodell --runtime-smoke-test`; optional synthetic tool round trip through `TaskRunner` with the in-process `SyntheticOrderTool` fixture | Fixed synthetic prompts; reports timings, token counts and throughput; reply text only with `--show-reply` |
| `ModelCatalog.swift` | `ModelArtifact`, `ModelCatalogSpec`, `ModelCatalog` (built-in catalog JSON), `effectiveCatalog`, `artifact(for:)` | Invalid catalog fails validation with no fallback; a policy catalog replaces the built-in one; approved hosts are exact names or subdomains |
| `ModelStore.swift` | `ModelStore` actor (download, resume, cancel, delete, import, verify, status stream), `ArtifactTransport` seam, `URLSessionArtifactTransport` | Size + SHA-256 before atomic promotion; redirects only to approved HTTPS hosts; body capped at `sizeBytes`; disk space + 512 MiB margin; changed files re-hashed before use |

`InferenceClient` and `ToolClient` make deterministic testing possible without a model, server or account. They are internal engineering seams, not a plugin authorization system.

## Application (`Sources/MinimodeLL`)

- `MinimodeLLApp.swift`: scene definitions plus menu, task workspace, settings and approval views. UI uses shared observable state and system materials. The task view shows the destination label (`AppState.destinationLabel`/`destinationSymbol`, from core `InferenceDestination`: this Mac, LAN · TLS, LAN · unencrypted, cloud) before submission.
- `AppState.swift`: loads/reloads policy, model selection, config and credential saves, task ownership, approval wait, user-safe error presentation. One shared `busy` state prevents concurrent tasks across windows. Reloads policy at submission and checks destination changes (whole provider equality). `testConnection(providerID:)` runs `ProviderProbe` and stores `probeNotice`/`probedModelIDs` for a later Settings UI. Owns the `RuntimeManager`, mirrors its state into `runtimeState`, picks `ManagedInferenceClient` for `managed` providers, stops the runtime when policy drops it, and calls `terminateForQuit()` on `willTerminate`.
- `MinimodeLLApp.swift` also contains `RuntimeStatus` (a minimal readiness line under the destination label; the menu shows the same summary and an "Unload local model" item) and `RuntimeSmokeCommand` (`--runtime-smoke-test [--tool] [--show-reply] [--hold N]`), which exits before any window is shown. It also holds `ModelsSettings`/`ModelRow` (the Settings → Models tab: status, Download, Cancel, Delete, Import via `fileImporter`) and `ModelDownloadCommand` (`--model-download [artifact-id]`, a headless verified download inside the sandbox).
- `AppState.swift` also owns the `ModelStore`, which is passed to the `RuntimeManager`. It mirrors artifact statuses and exposes download/cancel/delete/import. Deleting the artifact the policy uses stops the runtime first.

- `ProviderProbeCommand.swift`: `minimodell --probe-provider <id>`, the sandboxed connection test against the resolved policy (JSON with model IDs; exit 0 only when reachable).

### Design system (`Sources/MinimodeLL/Design`, spec in `docs/design/raycast-redesign.md`)

- `Tokens.swift`: `DesignPalette` (brand colors per scheme, plain values so offline rendering is deterministic), `Space`, `Radius`, `Typography` (Geist ramp), the `palette`/`opaqueMaterials` environment keys and `designRoot()`, which every design surface applies at its root (scheme → palette, base font, tint, Reduce Transparency → opaque materials).
- `Materials.swift`: `Material` (`NSVisualEffectView` `.hudWindow`/`.popover` with a rounded mask; opaque `surface` fallback), `cardChrome()`, `insetSurface()`.
- `Motion.swift`: durations/curves, `motion(_:value:)` (crossfade under Reduce Motion), `SectionTransition`, `PulseDot`.
- `Hotkey.swift`: `Hotkey` (text form ↔ Carbon key code/modifiers, requires ≥ 1 modifier, `UserDefaults` key `commandBarHotkey`, fallback ⌥Space) and `GlobalHotkey` (`RegisterEventHotKey`; sandbox-safe, no Accessibility permission, delivers only the registered combination).
- `DesignPreviews.swift`: `--render-design-previews <dir>` renders the command bar states light/dark with `ImageRenderer` (opaque materials, static text field, no scroll views) and exits; `BoundedScroll` and the `staticLayout` environment key.

### Command bar (`Sources/MinimodeLL/CommandBar`)

- `CommandBarState.swift`: `CommandBarPhase`, `Destination`, `CommandBarInputs` (plain facts) → `CommandBarModel.resolve` (pure; precedence locked › approval › running › error › result › typing › idle), `ProposalSummary`, `CommandBarActions`, `BarAction` list per phase. No policy or approval logic.
- `CommandBarView.swift`: the card (header with mark/input/destination chip, phase body, footer with key hints), `SuggestionList`, `ProgressSection`, `ApprovalCard`, `ResultSection`, `NoticeSection`, `ActionPanel` (⌘K), `CommandBarSession` (transient UI state: ⌘K open, selections, focus token, presented) and `CommandBarLayout` constants.
- `CommandBarPanel.swift`: borderless non-activating floating `NSPanel`, transparent, key-capable, `.transient`; placed under the pointer's screen at 22 % from the top and resized with its top edge anchored.
- `CommandBarController.swift`: owns the panel, hosting view (`preferredContentSize` sizing), hotkey registration (re-registers on `UserDefaults` change), the local key monitor (`handle(_:)`, the keyboard map), show/hide with fade, approval surfacing via `withObservationTracking`, and `CommandBarHost` + `AppState.commandBarInputs`. Every action calls `AppState` (`submit`, `cancel`, `decide`, `stopRuntime`, `selectedModel`).
- `CommandBarSettings.swift`: Settings → Command Bar tab (shortcut text, validation notices, registration status, "Show command bar").
- `MinimodeLLApp.swift` creates the controller in `init`, puts `MenuBarExtra` first so no window opens at launch, adds `--render-design-previews` and `--open-command-bar` (debug: shows the bar 0.6 s after launch), and passes the controller to `MenuContent` and `SettingsView`.

## Runtime guard (`Sources/RuntimeGuard/main.swift`)

`minimodell-runtime-guard <llama-server> [args…]`: posix_spawns the server with the inherited environment, forwards SIGTERM/SIGINT/SIGHUP and escalates to SIGKILL after 3 s, stops the server the same way when re-parented because the app died, and exits with the server status (128 + signal when signalled). No logging. Embedded only when the runtime is fetched.
- `BrowserAuthorization.swift`: retains ASWebAuthenticationSession and checked continuation, validates callback scheme/host, handles cancellation. SDK remains responsible for PKCE/state/protocol verification.

`BrandAssets.swift`, `MinimodeMark.swift` and `Resources/BrandAssets/` implement the supplied visual identity. See `docs/branding.md` for source mapping and `scripts/sync-brand-assets.py` for repeatable resource updates. Brand fonts are registered only in the app process.

## Diagnostics and tests

- `Sources/AgentDiagnostics/main.swift`: `--config` file or current-user policy validation; emits JSON metadata including `providerDestinations`, exits nonzero on failure; performs no network requests or inference unless `--probe-provider <id>` is given (then one `GET /models`, exit 2 when unreachable).
- `Tests/LocalAgentCoreTests/PolicyTests.swift`: endpoint/config/context/schema/audit tests and configuration fixture builder.
- `Tests/LocalAgentCoreTests/RunnerTests.swift`: fake inference/tools, action approval/rejection, input/output bounds, cancellation, duplicate IDs and audit failure. These are orchestration tests, not model accuracy tests.
- `Tests/LocalAgentCoreTests/RuntimeTests.swift`: `FakeHost`/`FakeProcess` lifecycle tests (startup, key handling, timeout, exit during startup, crash while ready, foreign/any-key servers, alias mismatch, idle unload with leases, stop escalation, quit, policy change, cancellation, guard launch), managed-provider validation, example-config decoding, and real loopback port reservation. No model or server is started.
- `Tests/LocalAgentCoreTests/LANProviderTests.swift`: LAN host classification (accepted/rejected sets), HTTP/`allowInsecureTransport` rules, URL credential/query/fragment rejection, flag-on-other-kinds rejection, resolved-address checks, request-time rejection before network use, model-list parsing, destination labels, LAN example config. No network is used.
- `Tests/LocalAgentCoreTests/ModelStoreTests.swift`: `FakeTransport` store tests and catalog/policy validation. Covers verify-before-promote, hash and size mismatch, oversize, cancellation cleanup, resume, disk-space refusal, catalog/host/allowDownloads gates, import verification, tamper re-verification, delete, the runtime launching only verified artifacts, and the runtime tag gate. No network is used.
- `Tests/MinimodeLLTests/` (`@testable import MinimodeLL`, no window or hotkey): `HotkeyTests.swift` (parsing, aliases, glyphs, rejection of bare keys, storage round trip and fallback), `CommandBarStateTests.swift` (phase precedence, destination mapping, submit gating, locked/managed status, per-phase actions, content-free status line), `CommandBarKeyTests.swift` (keyboard map through `CommandBarController.handle` with synthetic `NSEvent`s: ⌘K/esc, suggestion navigation, approval keys reaching `AppState.decide`, action list, pass-through). These construct a real `AppState`, which installs the starter config in the test process's Application Support if absent.
- `scripts/mock-inference.py`: optional local HTTP fixture for UI checks. It returns an explicitly labeled fixed response, does not run a model, and makes no outbound requests. It occupies port 9931 until stopped.

## Management and examples

- `Config/local.example.json`: mirrors the starter local provider/model stub.
- `Config/enterprise.example.json`: adds a LiteLLM placeholder and four OAuth MCP placeholder endpoints with empty tool allowlists.
- `Config/lan-lmstudio.example.json`: one `lan` provider (`http://192.168.1.50:1234/v1` placeholder, `allowInsecureTransport: true`, `credentialAccount` `lan.lmstudio`) and its model stub (placeholder model ID; use one reported by `--probe-provider`).
- `Config/bundled-runtime.example.json`: one `managed` provider referencing the built-in verified artifact `qwen3-4b-instruct-2507-q4_k_m`, and its single model stub (16 GB, 8,192 context).
- `scripts/make-profile.py`: converts a reviewed policy JSON file into a forced macOS preference profile. No credentials should be supplied.
- `scripts/mdm-readiness.sh`: shared read-only app-signature and explicit-policy validation for either Jamf or Kandji.
- `scripts/jamf-inventory.sh`: read-only architecture/RAM Extension Attribute.

## Common changes

- New provider behavior: extend the provider abstraction and policy validation; add tests; document data destination and credentials.
- New model: add a `ModelArtifact` (built-in catalog in `ModelCatalog.swift`, or a policy `modelCatalog`) with a pinned revision URL, size and SHA-256 taken from the host metadata and checked independently, license, template notes and runtime tags. Record live measurements in `docs/validation-results.md` and update ADR 0009 if the default changes.
- New MCP server: configuration first, then interoperability work only where required; do not hardcode vendor logic in the task runner.
- New configuration field: update Codable type, validation, both examples when relevant, configuration reference, managed-policy behavior and migration expectations.
- New execution safeguard: enforce in the core before the side effect, add a negative test proving execution did not occur, update security/architecture/state docs.
- Branding change: edit the resource, rebuild, and verify package name and OAuth identity implications.
