# 2026-09-23: MCP server management in Settings (WORK-017, issue #22)

Branch `feat/mcp-server-settings`, stacked on `feat/lan-inference` (PR #24) because that branch was not yet merged into `main` when this work started. If PR #24 merges first, this PR's diff against `main` shrinks to the WORK-017 commits only.

## Goal

Full create/read/update/delete of HTTPS (Streamable HTTP) MCP servers in Settings instead of raw JSON: display name, URL, enable/disable, auth mode (none, bearer token, native public OAuth), custom request headers with secret values in Keychain, a "Test connection" that lists offered tools for the user to approve, and read-only behavior under a forced managed policy.

## Findings before the change

- `MCPServerSpec` had `id`, `title`, `endpoint`, `credentialAccount`, `tools`, `oauth`; no public initializers, no enabled flag, no headers. Validation lived inline in `AgentConfiguration.validate()`.
- `MCPConnections` built the SDK transport inline and read the bearer token directly from `CredentialStore`, so it could not be tested without Keychain or a network.
- The pinned SDK (swift-sdk 0.12.1, `Sources/MCP/Base/Transports/HTTPClientTransport.swift`) exposes `requestModifier: (URLRequest) -> URLRequest`. It runs after the SDK sets `Accept`, `Content-Type`, `MCP-Protocol-Version`, `MCP-Session-Id` and the OAuth `Authorization`, for both POST requests and the optional GET SSE stream. The public initializer takes a `URLSessionConfiguration`, so tests can install a `URLProtocol` through `protocolClasses`. The SDK spells the session header `MCP-Session-Id`.
- There was no Keychain delete function.
- Settings had only the raw JSON editor (Configuration tab) and a generic Credentials tab.

## Changes

Core (`Sources/LocalAgentCore`):
- `Configuration.swift`: `MCPServerSpec` gains optional `enabled` and `headers`, public memberwise init, `isEnabled`, derived `authMode`, `oauthStorageAccount` (moved from `MCPConnections`, same derivation), `referencedAccounts`, and `validate()` (ID, nonblank title ≤ 100, HTTPS endpoint, OAuth/bearer exclusivity, nonempty credential account, tool name length and uniqueness, header policy). `ToolRule`/`OAuthSpec` get public inits and `Equatable`. The 16-tool budget now counts enabled servers only.
- New `MCPServerSettings.swift`: `MCPHeaderSpec`, `MCPHeaderPolicy` (token grammar, reserved names/prefixes, Authorization rule, value rules, account-name rule), `CredentialStoring` + `KeychainCredentials`, and `MCPServerStore` (create/update/enable/delete against the user `config.json`).
- `MCPConnections.swift`: `MCPTransportFactory` (bearer, OAuth, custom headers via `requestModifier`; injectable credentials and session configuration), `MCPConnections` skips disabled servers and takes a factory (default unchanged for `AppState`), `MCPServerProbe` + `DiscoveredTool` for Test connection, including `discoverToolsUnderCurrentPolicy` which resolves policy itself.
- `Credentials.swift`: `CredentialStore.delete(account:)`.

App (`Sources/MinimodeLL`):
- New `MCPServersSettingsView.swift`: list with enable switch, Add/Edit sheet (ID immutable after creation, display name, URL, enabled, auth mode picker, `SecureField` token, OAuth client ID, header rows with Secret checkbox and `SecureField` for secret values, Test connection with tool checkboxes and per-tool "Ask before running"), delete confirmation dialog explaining Keychain cleanup, locked banner and read-only editor when managed. Standard controls only.
- `MinimodeLLApp.swift`: two one-line edits: the new tab in `SettingsView`, and the workspace sidebar lists enabled servers only.

Tests: new `Tests/LocalAgentCoreTests/MCPServerSettingsTests.swift` (17 test functions, some parameterized), including `MockMCPServer`, an in-process Streamable HTTP MCP fixture implemented as a `URLProtocol` (initialize, notifications → 202, tools/list, GET → 405, optional required-header → 401), and `FakeCredentials`.

Config/CI: new `Config/mcp-servers.example.json` (bearer server with inline + secret header and two tool rules; disabled OAuth server), validated in CI.

Docs: ADR 0012, configuration reference (MCP server object, custom headers, editor behavior, migration), architecture (new section), code map, decisions index, site navigation (ADR 0012 page), `CLAUDE.md` one bullet.

## Decisions (see ADR 0012)

- Kept existing JSON keys (`title`, `endpoint`) instead of the `displayName`/`url` names in the task text, for backward compatibility with existing configs and managed policies. The UI labels them "Display name" and "URL".
- Auth mode is derived from `credentialAccount`/`oauth`, not a new key.
- Reserved header list and prefixes as documented; `Authorization` only with auth mode none and only as a secret; cookies unsupported.
- Server IDs immutable in the editor so Keychain ownership (`mcp.<id>.` prefix) is stable.
- Keychain cleanup deletes only owned accounts that nothing else references; hand-written accounts are never deleted.
- Test connection under a managed policy is limited to the policy's own definitions without secret overrides, enforced in core (`discoverToolsUnderCurrentPolicy` reloads policy; `discoverTools(managedPolicy:)` checks).
- The editor rewrites `config.json` with sorted keys but preserves unknown keys.

## Validation actually run (this Mac: macOS 15.7.7 / Darwin 24.6, Apple Silicon, 32 GB, Swift 6.1 toolchain)

- `swift build`: passed, no warnings in changed files.
- `swift test`: 88 tests passed (71 before this branch + 17 new test functions).
  - Header delivery was checked through the real SDK `HTTPClientTransport` and `Client` against the `URLProtocol` fixture: inline header, Keychain-backed (fake) secret header and bearer token present on every POST; `Content-Type` still `application/json`; the SDK's session header still the server-issued value; only the allowlisted tool exposed.
  - Test connection with unsaved secrets returned all three offered tools with `schemaSupported` flags (a `$ref` schema marked unsupported) and saved nothing.
  - A missing secret fails before any request reaches the fixture; a disabled server is never contacted.
- `minimodell-diagnostics --config` on all five examples (local, enterprise, bundled-runtime, lan-lmstudio, mcp-servers): exit 0. A copy of the MCP example with a `Host` header: exit 1.
- `site/build.py` + `site/check.py` with the hash-pinned requirements: 32 pages checked, 0 problems.
- `scripts/package-app.sh` + `codesign --verify --strict build/minimodeLL.app`: passed.
- Packaged app launched (`open build/minimodeLL.app`) with the existing container config (no MCP servers): process alive after 6 s, then quit with `pkill -x minimodell`. The container `config.json` SHA-256 was identical before and after; it was not edited.

## Not tested

- No real MCP server (none available). Live interoperability, OAuth sign-in via Test connection, and vendor-specific header requirements are untested.
- No live HTTPS Streamable HTTP fixture: the app requires HTTPS for MCP, and a local TLS fixture would need a trusted certificate; judged not cheap. The `URLProtocol` fixture exercises the SDK transport and the app's header code but not TLS, redirects, SSE responses, or URLSession's own handling of `Authorization`.
- The Settings UI was not exercised interactively or visually (no Screen Recording permission for `screencapture`; `osascript` System Events avoided). The add/edit/delete/test flows in the UI are covered only by the core tests of what they call.
- Real Keychain reads/writes/deletes from `MCPServerStore` inside the sandbox were not run (tests use `FakeCredentials`); `CredentialStore.delete` is untested against the real Keychain.
- Managed-policy locking was tested with an injected `isManaged` closure, not with a real forced profile.

## Remaining work and suggestions

- Owner live test with a real MCP service (see "needs owner" in the PR): add a server in Settings, test connection, approve tools, run a task.
- Consider `minimodell --probe-mcp <server-id>` (sandboxed CLI like `--probe-provider`) for headless checks.
- `allowUserHTTPServers` managed switch (issue #15) to allow user-added servers alongside managed policy.
- A sign-out / revoke control for OAuth servers (delete only clears on server deletion or binding change).
- MCP response buffering still has no pre-decode byte cap.

## Suggested text for shared docs (coordinator)

- **CHANGELOG (Unreleased):** "Settings → MCP Servers: add, edit, enable/disable, delete and test HTTPS MCP servers; per-server auth mode (none, bearer, OAuth), custom request headers with secret values in Keychain, and tool approval from discovered tools. Managed servers are read-only. New optional `enabled` and `headers` keys (ADR 0012)."
- **project-state.md:** "MCP servers can be managed in Settings (WORK-017, ADR 0012). Core validation, editor, header injection and Test connection are unit-tested against an in-process Streamable HTTP fixture; no live MCP service has been tested; the Settings UI has not been visually verified."
- **backlog.md:** WORK-017 → "Implemented on `feat/mcp-server-settings` (PR pending review); live MCP interoperability pending owner test." Follow-ups: sandboxed `--probe-mcp` CLI; OAuth sign-out; `allowUserHTTPServers` (#15).
- **handoff.md:** next action for WORK-017 is the owner's live test with a real MCP server; note that older builds ignore `enabled`/`headers` (roll out app before policy).
- **validation-results.md:** the validation list above, dated 2026-09-23, environment as stated, with the "Not tested" list.
- **sessions/README.md:** add `2026-09-23-mcp-server-settings.md`: MCP server management (WORK-017, #22).
