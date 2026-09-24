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
- `.github/workflows/ci.yml`: macOS test, example policy validation (three examples), app packaging without and with the fetched runtime plus nested-signature/entitlement checks, profile generation/lint. Hosted execution must be checked, not inferred from local success.

## Core (`Sources/LocalAgentCore`)

| File | Responsibility | Important boundary |
| --- | --- | --- |
| `Brand.swift` | Reads branding, stable identity, support directory | Packaged app/CLI resource lookup precedes SwiftPM fallback |
| `Resources/Branding.json` | Display name, version, bundle identity | Identity changes affect policy, Keychain and callbacks |
| `Configuration.swift` | Codable schema, endpoint/ID/limit validation, source precedence | Forced managed policy replaces user config; invalid forced policy throws |
| `Inference.swift` | Chat/tool DTOs, `InferenceClient`, compatible HTTP client, context estimate | Refuses redirects, caps HTTP response at 262,144 bytes, sends nonstreaming Chat Completions |
| `MCPConnections.swift` | SDK client lifecycle, paginated discovery, aliases, allowlists, text results | At most 10 discovery pages; OAuth storage bound to endpoint and client ID hash |
| `Credentials.swift` | Keychain bearer storage and OAuth `TokenStorage` adapter | Tokens never enter configuration files; persistence failure behavior is limited |
| `ToolSchema.swift` | Supported schema subset and argument checks | Unsupported validation keywords fail closed |
| `TaskRunner.swift` | Input admission, model selection, model/tool loop, approvals, cancellation, audit | One call per model step, bounded calls, no automatic write retries |
| `Audit.swift` | Actor-owned JSONL rotation and OSLog metadata | No task content fields; write failure blocks progression |
| `Runtime.swift` | `RuntimeState`, `RuntimeEndpoint`, `RuntimeProcess`/`RuntimeHost` seams, `RuntimeManager` actor, `ManagedInferenceClient` | Per-launch key never logged/persisted; key-challenge readiness; leases gate idle unload; crash → `failed`, no auto restart or cloud fallback |
| `RuntimeHost.swift` | `SystemRuntimeHost`: loopback port reservation, `Process` launch with explicit env and discarded output, loopback-only bounded probes | Refuses non-loopback probe URLs and redirects |
| `RuntimeSmokeTest.swift` | Content-free end-to-end runtime check used by `minimodell --runtime-smoke-test` | Fixed synthetic prompt; reports timings/byte counts only |

`InferenceClient` and `ToolClient` make deterministic testing possible without a model, server or account. They are internal engineering seams, not a plugin authorization system.

## Application (`Sources/MinimodeLL`)

- `MinimodeLLApp.swift`: scene definitions plus menu, task workspace, settings and approval views. UI uses shared observable state and system materials. The task view shows local/cloud destination before submission.
- `AppState.swift`: loads/reloads policy, model selection, config and credential saves, task ownership, approval wait, user-safe error presentation. One shared `busy` state prevents concurrent tasks across windows. Reloads policy at submission and checks destination changes (whole provider equality). Owns the `RuntimeManager`, mirrors its state into `runtimeState`, picks `ManagedInferenceClient` for `managed` providers, stops the runtime when policy drops it, and calls `terminateForQuit()` on `willTerminate`.
- `MinimodeLLApp.swift` also contains `RuntimeStatus` (minimal readiness line under the destination label; menu shows the same summary and an "Unload local model" item) and `RuntimeSmokeCommand` (`--runtime-smoke-test [--hold N]`, exits before any window is shown).

## Runtime guard (`Sources/RuntimeGuard/main.swift`)

`minimodell-runtime-guard <llama-server> [args…]`: posix_spawns the server with the inherited environment, forwards SIGTERM/SIGINT/SIGHUP and escalates to SIGKILL after 3 s, stops the server the same way when re-parented because the app died, and exits with the server status (128 + signal when signalled). No logging. Embedded only when the runtime is fetched.
- `BrowserAuthorization.swift`: retains ASWebAuthenticationSession and checked continuation, validates callback scheme/host, handles cancellation. SDK remains responsible for PKCE/state/protocol verification.

`BrandAssets.swift`, `MinimodeMark.swift` and `Resources/BrandAssets/` implement the supplied visual identity. See `docs/branding.md` for source mapping and `scripts/sync-brand-assets.py` for repeatable resource updates. Brand fonts are registered only in the app process.

## Diagnostics and tests

- `Sources/AgentDiagnostics/main.swift`: `--config` file or current-user policy validation; emits JSON metadata, exits nonzero on failure; performs no network requests or inference.
- `Tests/LocalAgentCoreTests/PolicyTests.swift`: endpoint/config/context/schema/audit tests and configuration fixture builder.
- `Tests/LocalAgentCoreTests/RunnerTests.swift`: fake inference/tools, action approval/rejection, input/output bounds, cancellation, duplicate IDs and audit failure. These are orchestration tests, not model accuracy tests.
- `Tests/LocalAgentCoreTests/RuntimeTests.swift`: `FakeHost`/`FakeProcess` lifecycle tests (startup, key handling, timeout, exit during startup, crash while ready, foreign/any-key servers, alias mismatch, idle unload with leases, stop escalation, quit, policy change, cancellation, guard launch), managed-provider validation, example-config decoding, and real loopback port reservation. No model or server is started.
- `scripts/mock-inference.py`: optional local HTTP fixture for UI checks. It returns an explicitly labeled fixed response, does not run a model, and makes no outbound requests. It occupies port 9931 until stopped.

## Management and examples

- `Config/local.example.json`: mirrors the starter local provider/model stub.
- `Config/enterprise.example.json`: adds a LiteLLM placeholder and four OAuth MCP placeholder endpoints with empty tool allowlists.
- `Config/bundled-runtime.example.json`: one `managed` provider with a placeholder `approved-model.gguf` and its single model stub.
- `scripts/make-profile.py`: converts a reviewed policy JSON file into a forced macOS preference profile. No credentials should be supplied.
- `scripts/mdm-readiness.sh`: shared read-only app-signature and explicit-policy validation for either Jamf or Kandji.
- `scripts/jamf-inventory.sh`: read-only architecture/RAM Extension Attribute.

## Common changes

- New provider behavior: extend the provider abstraction and policy validation; add tests; document data destination and credentials.
- New model: update a reviewed catalog/configuration now; future verified manifests will own artifact/template provenance.
- New MCP server: configuration first, then interoperability work only where required; do not hardcode vendor logic in the task runner.
- New configuration field: update Codable type, validation, both examples when relevant, configuration reference, managed-policy behavior and migration expectations.
- New execution safeguard: enforce in the core before the side effect, add a negative test proving execution did not occur, update security/architecture/state docs.
- Branding change: edit the resource, rebuild, and verify package name and OAuth identity implications.
