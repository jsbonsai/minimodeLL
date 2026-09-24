# ADR 0012: MCP server management in Settings, custom headers, and auth modes

Date: 2026-09-23. Status: Accepted. Implemented on `feat/mcp-server-settings` (WORK-017, issue #22). Extends [ADR 0005](0005-mcp-and-native-oauth.md); relies on [ADR 0002](0002-optional-managed-policy.md) for managed-policy behavior.

## Context

Until now an MCP server could only be added by editing raw JSON in the Configuration tab. The owner wants full create, read, update and delete for HTTPS (Streamable HTTP) MCP servers in Settings, including:

- an auth mode per server (none, bearer token, native public OAuth client),
- custom HTTP request headers, some of which are secrets (API keys, tenant tokens),
- a "Test connection" that shows the tools a server offers so the user can pick an allowlist.

Custom headers are a new way to put credentials and protocol state on the wire. A header can break framing (`Content-Length`, `Transfer-Encoding`), hijack protocol negotiation (`Mcp-Session-Id`, `Mcp-Protocol-Version`), smuggle state (`Cookie`, `Proxy-Authorization`), inject further headers through CR/LF, or leak a secret into `config.json`, a managed profile, or a support bundle.

## Decision

1. **Schema (backward compatible, schema version stays 1).** `MCPServerSpec` keeps its original keys (`id`, `title`, `endpoint`, `credentialAccount`, `tools`, `oauth`) and gains two optional keys:
   - `enabled` (boolean; absent means enabled). A disabled server is never connected, and its tools do not count toward the 16-tool budget.
   - `headers`: an array of `{ "name", "value" }` (non-secret, stored in configuration) or `{ "name", "secretAccount" }` (the value is in Keychain under that account in the app's service). Exactly one of `value` or `secretAccount`.

   The auth mode is derived, not a new key: `oauth` set → OAuth; `credentialAccount` set → bearer; neither → none. Both set is still rejected. The task text asked for `displayName` and `url`; the existing `title` and `endpoint` keys were kept so existing configurations and managed policies keep working unchanged.
2. **Header rules (`MCPHeaderPolicy`, LocalAgentCore).**
   - Names: 1–64 characters of the RFC 9110 `token` grammar; unique case-insensitively; at most 16 headers per server.
   - Reserved names (case-insensitive), always rejected: `Host`, `Content-Length`, `Content-Type`, `Content-Encoding`, `Accept`, `Accept-Encoding`, `Connection`, `Keep-Alive`, `Transfer-Encoding`, `TE`, `Trailer`, `Upgrade`, `Expect`, `Cookie`, `Cookie2`, `Set-Cookie`, `WWW-Authenticate`, `Mcp-Session-Id`, `Mcp-Protocol-Version`, `Last-Event-ID`, `Cache-Control`, `Origin`, `Forwarded`, `Via`, `Range`, `If-Range`, `Date`; and every name starting with `Proxy-`, `Sec-` or `Mcp-` (the last reserves the protocol's namespace for future versions).
   - `Authorization`: rejected when the auth mode is bearer or OAuth (the mode owns it). Allowed when the mode is none, but only as a secret header, so a custom scheme such as `Basic` or `Token` never sits in plain configuration.
   - Values (inline and secret, checked at save time and again at request time): 1–4096 bytes of printable ASCII plus inner space/tab; no CR, LF, NUL or other control characters, no non-ASCII bytes, no leading or trailing whitespace. This prevents header injection and ambiguous encodings.
   - Keychain account names for secret headers: `[A-Za-z0-9_.:@-]{1,128}`.
   - Cookies are deliberately unsupported: the transport uses an ephemeral session, and cookie auth would need a cookie-jar and expiry design that is out of scope.
3. **Injection point.** The pinned SDK's `HTTPClientTransport` (0.12.1) accepts a `requestModifier` that runs after the SDK sets `Accept`, `Content-Type`, `Mcp-Protocol-Version`, `Mcp-Session-Id` and OAuth `Authorization`, on both POST and the optional GET event stream. `MCPTransportFactory` resolves header values (inline, or from Keychain) once per connection, validates them, and sets them in that modifier. The modifier skips reserved names again as defense in depth. `URLSessionConfiguration.httpAdditionalHeaders` was not used: per-request headers take precedence over it, so the app could not reason about which value wins, and the existing bearer token already goes through the modifier. Header values and tokens are never logged; error messages name only the header or account.
4. **Editor (`MCPServerStore`, LocalAgentCore).** Create, update, enable/disable and delete operate on the user `config.json`:
   - Every edit re-checks `ConfigurationLoader.isManaged()` and refuses while a forced managed policy is active (and if that check itself fails). Managed servers are shown read-only; the user cannot add servers alongside a managed policy because forced policy replaces the whole configuration (ADR 0002). A future `allowUserHTTPServers` switch is tracked in issue #15.
   - Only the `mcpServers` array is replaced; other keys in the file are preserved as JSON (written with sorted keys). The complete resulting configuration is decoded and validated before anything is written, and the write is atomic.
   - Server IDs are immutable after creation (delete and re-add instead), so Keychain ownership never moves.
   - Secrets typed in the editor are written only to Keychain accounts that the edited server references; a secret for any other account is refused, so one server's edit cannot overwrite another item.
   - The editor generates accounts `mcp.<serverID>.bearer` and `mcp.<serverID>.header.<lowercased-name>`. Deleting a server, removing a secret header, or changing an OAuth endpoint/client binding deletes only accounts the server **owned** (that `mcp.<serverID>.` prefix, or its derived OAuth token account) and only if no remaining server or provider references them. Hand-written account names without that prefix are never deleted.
5. **Test connection (`MCPServerProbe`).** Connects with the draft settings (unsaved secrets are passed in memory, never saved by testing), lists tools with the existing 10-page limit plus a 200-tool cap, truncates descriptions to 300 characters, marks tools whose input schema falls outside `ToolSchema`'s subset, and disconnects. Nothing is executed. Offering a tool does not approve it: the allowlist remains the explicit `tools` array with per-tool `requiresConfirmation` (default on in the UI), and unknown tools stay blocked at discovery. Under a forced policy, only a server exactly as the policy defines it may be tested, and without secret overrides, so a managed Mac cannot be used to send headers or credentials to an arbitrary endpoint.
6. **UI.** A new Settings tab, `MCPServersSettingsView.swift`, built from standard SwiftUI controls (list, sheet, `SecureField` for secrets, confirmation dialog for delete, checkboxes for tools) so the visual redesign can restyle it. It holds no policy logic.

## Alternatives considered

- **Store all header values in configuration.** Simpler, but puts API keys in `config.json`, managed profiles and support bundles. Rejected.
- **Allow any header name.** Rejected; see Context. A deny list plus a token grammar is simpler to reason about than an allow list that would block legitimate vendor headers (`X-Api-Key`, `X-Tenant`, and so on).
- **A new explicit `auth` key.** Would duplicate the existing `credentialAccount`/`oauth` fields and break older builds. Deriving the mode keeps the schema stable.
- **Custom `URLSession` / `URLProtocol` wrapper around the SDK.** More code and more ways to diverge from the SDK's transport; `requestModifier` is the SDK's supported hook.

## Consequences

- Older app builds ignore the unknown `enabled` and `headers` keys. A policy that disables a server with `enabled: false` would be **connected** by an older build, and headers would be silently dropped. Roll out the app before relying on these keys in managed policy.
- A header value saved in Keychain is read when a task or test connects. The first read by a newly signed build may show a Keychain access prompt.
- If writing `config.json` fails after new secrets were saved, those Keychain items remain until the server is saved again or deleted. Nothing references them, so they are inert.
- MCP response buffering is still not protected by a pre-decode byte cap (unchanged; see configuration reference).

## Validation

Unit tests (`MCPServerSettingsTests`) cover the schema, header rules, store behavior under managed policy, Keychain ownership on delete, and header delivery through the real SDK transport to an in-process Streamable HTTP fixture (`URLProtocol`). No live MCP server was available; live interoperability with the owner's services remains the acceptance gate.
