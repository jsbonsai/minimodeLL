# Code map and change entry points

## Build and package

- `Package.swift`: Swift 6.1 package, macOS 14 minimum, library/app/CLI/test targets, exact MCP SDK 0.12.1 dependency, branding resource.
- `Package.resolved`: transitive dependency lock. Commit intentional resolution changes and explain them. Some resolved dependencies are for SDK targets that this app does not compile; do not assume every resolved package is shipped.
- `packaging/App.entitlements`: App Sandbox, outbound network, user-selected read-only file access. No inference server/helper entitlement exists yet.
- `scripts/package-app.sh`: builds SwiftPM products, creates Info.plist, copies branding/licenses, signs CLI and app, verifies app signature. Defaults to debug and ad-hoc signing.
- `scripts/package-dmg.sh`: release build and drag-to-Applications image; optional application-certificate signing.
- `scripts/package-pkg.sh`: release build and `/Applications` component package; optional installer-certificate signing.
- `.github/workflows/ci.yml`: macOS test, example policy validation, app packaging, profile generation/lint. Hosted execution must be checked, not inferred from local success.

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

`InferenceClient` and `ToolClient` make deterministic testing possible without a model, server or account. They are internal engineering seams, not a plugin authorization system.

## Application (`Sources/MinimodeLL`)

- `MinimodeLLApp.swift`: scene definitions plus menu, task workspace, settings and approval views. UI uses shared observable state and system materials. The task view shows local/cloud destination before submission.
- `AppState.swift`: loads/reloads policy, model selection, config and credential saves, task ownership, approval wait, user-safe error presentation. One shared `busy` state prevents concurrent tasks across windows. Reloads policy at submission and checks destination changes.
- `BrowserAuthorization.swift`: retains ASWebAuthenticationSession and checked continuation, validates callback scheme/host, handles cancellation. SDK remains responsible for PKCE/state/protocol verification.

`BrandAssets.swift`, `MinimodeMark.swift` and `Resources/BrandAssets/` implement the supplied visual identity. See `docs/branding.md` for source mapping and `scripts/sync-brand-assets.py` for repeatable resource updates. Brand fonts are registered only in the app process.

## Diagnostics and tests

- `Sources/AgentDiagnostics/main.swift`: `--config` file or current-user policy validation; emits JSON metadata, exits nonzero on failure; performs no network requests or inference.
- `Tests/LocalAgentCoreTests/PolicyTests.swift`: endpoint/config/context/schema/audit tests and configuration fixture builder.
- `Tests/LocalAgentCoreTests/RunnerTests.swift`: fake inference/tools, action approval/rejection, input/output bounds, cancellation, duplicate IDs and audit failure. These are orchestration tests, not model accuracy tests.
- `scripts/mock-inference.py`: optional local HTTP fixture for UI checks. It returns an explicitly labeled fixed response, does not run a model, and makes no outbound requests. It occupies port 9931 until stopped.

## Management and examples

- `Config/local.example.json`: mirrors the starter local provider/model stub.
- `Config/enterprise.example.json`: adds a LiteLLM placeholder and four OAuth MCP placeholder endpoints with empty tool allowlists.
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
