# Configuration reference — schema version 1

Authoritative implementation: `Sources/LocalAgentCore/Configuration.swift`. JSON is used for both local configuration and managed `PolicyJSON`; YAML is not implemented. Secrets belong in Keychain.

## Source precedence and update behavior

When the `PolicyJSON` preference is forced by MDM in the stable bundle domain, its string value supplies the complete configuration. Invalid type, invalid JSON or validation failure blocks requests. Otherwise, the app reads its user `config.json` or starter defaults. `defaults write` alone does not make policy forced.

The app installs a starter file if missing and reads policy on startup/reload and before every task. The resulting configuration is fixed for that task. User settings cannot append to a managed allowlist. MDM removal permits local configuration again; this is intentional current behavior and should be included in fleet testing.

In the packaged app, `UserDefaults.standard` reads its own domain. A diagnostics/development process with a different bundle identity opens the explicit preference suite. Do not replace the app's own standard defaults with a suite of the same name: that returned nil and caused a launch crash during initial validation.

## Root fields

All fields below are required unless identified as optional in their nested object.

| Field | Type | Meaning |
| --- | --- | --- |
| `schemaVersion` | integer | Exactly `1` |
| `systemPrompt` | string | Behavior guidance; not an authorization mechanism |
| `providers` | array | Local or LiteLLM connection definitions |
| `models` | array | At least one approved model stub |
| `mcpServers` | array | May be empty; defines permitted remote service connections |
| `limits` | object | Bounded task execution settings |

Provider, model and MCP server IDs must each be unique within their collection and match `[A-Za-z0-9_-]{1,64}`. Cross-collection reuse is allowed. Unknown JSON keys are currently ignored by Codable, so do not rely on decoding to catch every typo. Future schema evolution should specify migrations and unknown-key handling.

## Provider object

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Reference used by model stubs |
| `kind` | yes | `local` or `litellm` |
| `baseURL` | yes | API base, normally ending in `/v1`; app appends `chat/completions` |
| `credentialAccount` | no | Keychain account for a bearer token |

Local URLs must use HTTP and a literal loopback host (`127.0.0.1` or IPv6 loopback). `localhost` is intentionally rejected by current validation. Remote providers require HTTPS. Credentials in the URL, query strings and fragments are rejected for all configured endpoints. The inference client rejects redirects and requires HTTP 200.

A missing configured credential fails the run. Omitting `credentialAccount` sends no bearer header. This is useful for development but is not the planned authentication model for a bundled runtime. Selecting a LiteLLM model is explicit; there is no local-to-cloud fallback.

## Model object

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Stable app catalog ID |
| `title` | yes | Display label |
| `providerID` | yes | Must reference a configured provider |
| `model` | yes | Nonempty exact alias sent to the provider |
| `minimumMemoryGB` | yes | Nonnegative total physical memory threshold; enforced for local models |
| `contextTokens` | yes | 2,048–131,072; must exceed output token limit |

`minimumMemoryGB` uses bytes divided by 1,073,741,824. It does not reserve memory or account for other applications. A cloud model is not subject to local model-memory eligibility. A stub currently has no file URL, checksum, quantization, template, license or runtime revision. Those belong to upcoming artifact management.

## MCP server object

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Stable service ID |
| `title` | yes | Display label |
| `endpoint` | yes | HTTPS Streamable HTTP MCP endpoint |
| `tools` | yes | Explicit tool rules; empty means no discovery/connection for this server |
| `credentialAccount` | no | Keychain account for pre-supplied bearer token |
| `oauth` | no | Public native OAuth client configuration |

Use at most one of `credentialAccount` and `oauth`. A server with neither is attempted without authentication. All configured tool rules across all servers must total at most 16. Names must be unique within a server. The examples intentionally contain no enabled tools and no real company URLs.

A tool rule has `name` (exact MCP tool name) and `requiresConfirmation` (boolean). This boolean is app policy, not inherited from the server's annotations. Setting it false permits automatic execution when selected by the model. Explicitly review each rule before deploying it. The model receives temporary aliases; the app resolves aliases back to the approved service/name pair.

Discovery processes up to 10 pages per server. Approved schemas outside the supported subset block the run. Execution accepts text results only. See the architecture document for schema details and transport-memory limitations.

## OAuth object

`clientID` is a required nonblank string. Register a public native client with callback `<bundleIdentifier>://oauth-callback`; the default is `org.minimodell.agent://oauth-callback`. Authorization uses the SDK plus the system browser session. No shared client secret field is implemented.

OAuth tokens are stored under an account derived from server ID and a SHA-256 binding of endpoint plus client ID. Reusing a server ID for another endpoint/client does not select the old OAuth storage account. Raw bearer accounts remain explicitly named by the operator. There is not yet a logout/revoke credentials UI.

Existing LibreChat client registrations may be confidential web clients or have incompatible redirects. Determine compatibility per service; do not copy secrets into this file.

## Limits

| Field | Starter value | Accepted range | Enforcement |
| --- | --- | --- | --- |
| `inputBytes` | 2,048 | 1–16,384 | UTF-8 size of initial task text |
| `outputTokens` | 768 | 64–4,096 | Sent as `max_tokens` per model response and reserved in context estimate |
| `maxToolCalls` | 4 | 0–12 | Total executed tool calls in a task |
| `toolResultBytes` | 2,048 | 128–32,768 | UTF-8 text size after SDK result decoding |
| `timeoutSeconds` | 120 | 10–300 | Task deadline plus inference HTTP timeouts |

The context estimate includes encoded message history and tool definitions, output reservation, and a 512-unit framing allowance. UTF-8 bytes are used conservatively; this is not exact tokenization. Oversized tool results are rejected, not silently truncated. An output with provider finish reason `length` is treated as an incomplete task.

The inference response has a separate fixed 262,144-byte transport cap. MCP buffering is not yet protected by an equivalent pre-decode byte cap. Cancellation and timeout do not undo external actions already accepted by a service.

## Validate and deploy

```sh
swift run minimodell-diagnostics --config Config/enterprise.example.json
scripts/make-profile.py Config/enterprise.example.json build/minimodell.mobileconfig
plutil -lint build/minimodell.mobileconfig
```

The profile generator checks that input parses as JSON but does not run the Swift validator. Always validate first. Diagnostics is metadata-only and cannot prove service connectivity, model quality, OAuth correctness or real MDM delivery.
