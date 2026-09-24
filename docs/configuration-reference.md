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
| `providers` | array | Local, LAN, LiteLLM or managed-runtime connection definitions |
| `models` | array | At least one approved model stub |
| `mcpServers` | array | May be empty; defines permitted remote service connections |
| `limits` | object | Bounded task execution settings |
| `modelCatalog` | object, **optional** | Approved model artifacts and download hosts (below). Absent: the built-in catalog |

Provider, model and MCP server IDs must each be unique within their collection and match `[A-Za-z0-9_-]{1,64}`. Cross-collection reuse is allowed. Unknown JSON keys are currently ignored by Codable, so do not rely on decoding to catch every typo. Future schema evolution should specify migrations and unknown-key handling.

## Provider object

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Reference used by model stubs |
| `kind` | yes | `local`, `lan`, `litellm` or `managed` |
| `baseURL` | `local`/`lan`/`litellm` only | API base, normally ending in `/v1`; app appends `chat/completions` (and `models` for the connection test). Must be absent for `managed` |
| `credentialAccount` | no | Keychain account for a bearer token. Must be absent for `managed` |
| `runtime` | `managed` only | App-owned bundled runtime settings (below). Must be absent for `local`/`lan`/`litellm` |
| `allowInsecureTransport` | `lan` only, optional | `true` permits a plain `http` LAN URL. Rejected on every other kind and on an `https` LAN URL (ADR 0011) |

`local` means an externally started loopback server that the app does not own. `managed` means the app launches, verifies, unloads and stops its own bundled `llama-server` (ADR 0008).

`lan` means an OpenAI-compatible server on the local network that the app does not own (LM Studio, Ollama, `llama-server`); see [LAN providers](#lan-providers-kind-lan) below.

Local URLs must use HTTP and a literal loopback host (`127.0.0.1` or IPv6 loopback). `localhost` is intentionally rejected by current validation. Remote providers require HTTPS. Credentials in the URL, query strings and fragments are rejected for all configured endpoints. The inference client rejects redirects and requires HTTP 200.

A missing configured credential fails the run. Omitting `credentialAccount` sends no bearer header. This is useful for development with an external server; the `managed` runtime instead uses a random per-launch key that is never configured or stored. Selecting a LiteLLM model is explicit; there is no local-to-cloud fallback.

### LAN providers (`kind: "lan"`)

Authoritative implementation: `Sources/LocalAgentCore/LANProvider.swift` (`LANHost`, `ProviderProbe`) and `AgentConfiguration.validateLANEndpoint` (ADR 0011).

| Host form | Accepted |
| --- | --- |
| IPv4 literal | 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16 (except 169.254.169.254). Strict dotted decimal only |
| IPv6 literal | fc00::/7 (ULA), fe80::/10 (link-local, optional `%zone`, written `[fe80::1%25en0]` in the URL) |
| Name | `<label>.local` mDNS names (letters, digits, hyphens) |
| Anything else | Rejected: public IPs, loopback (use `local`), 100.64/10, IPv4-mapped IPv6, `localhost`, and every non-`.local` DNS name (`lmstudio`, `lmstudio.lan`, `*.home.arpa`, public names), over HTTP **and** HTTPS |

Transport and request rules:

- `https` is always allowed. `http` requires `"allowInsecureTransport": true` on that provider. The destination label then reads `LAN · unencrypted`, and prompts, tool results and any bearer token cross the network in plain text.
- Credentials in the URL, query strings and fragments are rejected, redirects are refused, and HTTP 200 is required, as for other providers.
- Before every request the endpoint is validated again. A `.local` name is resolved again through the system resolver (mDNS). The request is refused if any resolved address is outside the LAN ranges above, or if the name does not resolve. A small DNS-rebinding window remains between this check and URLSession's own lookup; use HTTPS or a literal IP when the local network is not trusted (ADR 0011).
- `credentialAccount` is optional. LM Studio (Developer → server settings → require API key) and `llama-server --api-key` accept a bearer token. Save the token in the Credentials tab under that account.
- `lan` is not on-device inference, so `minimumMemoryGB` is not enforced (set it to 0).
- The label before submission is `LAN · TLS · your request and tool results are sent to <host>` or `LAN · unencrypted · … in plain text`.
- The packaged app declares `NSAllowsLocalNetworking` (ATS) and `NSLocalNetworkUsageDescription`. On macOS 15 the first connection to another LAN host may show the system Local Network prompt; denying it makes requests fail.

Test connection (lists the model IDs the server reports at `GET <baseURL>/models`; prints IDs only, never bodies or tokens):

```sh
swift run minimodell-diagnostics --config my-config.json --probe-provider lan-lmstudio   # unsandboxed; exit 2 when unreachable
build/minimodeLL.app/Contents/MacOS/minimodell --probe-provider lan-lmstudio            # sandboxed, uses the resolved policy
```

Use a returned ID as the model stub's `model`. LM Studio uses its loaded model identifiers; Ollama uses `name:tag`; `llama-server` uses its `--alias`.

Example (`Config/lan-lmstudio.example.json`; `192.168.1.50` and the model ID are placeholders):

```json
{"id": "lan-lmstudio", "kind": "lan", "baseURL": "http://192.168.1.50:1234/v1",
 "allowInsecureTransport": true, "credentialAccount": "lan.lmstudio"}
```

Typical base URLs: LM Studio `http://<ip>:1234/v1`, Ollama `http://<ip>:11434/v1` (set `OLLAMA_HOST=0.0.0.0` on the server), and `llama-server --host <lan ip> --port 8080` gives `http://<ip>:8080/v1`. By default each of these servers listens only on its own loopback address. Exposing one to the LAN is a decision about the server Mac.

Managed policy: a forced `PolicyJSON` replaces the whole configuration, so a LAN provider exists under management only if the administrator lists one. There is no separate LAN switch. Migration: schema version stays `1`, and existing configurations are unchanged. Older builds reject `"kind": "lan"` (unknown value), and that rejection fails closed, so update the app before you deploy a policy that contains a LAN provider.

### Managed runtime object (`runtime`)

| Field | Required | Default | Accepted | Meaning |
| --- | --- | --- | --- | --- |
| `artifact` | one of `artifact`/`modelFile` | — | `^[A-Za-z0-9_.-]{1,64}$`, must exist in the effective model catalog | Approved artifact ID. The file must pass size + SHA-256 verification before launch (ADR 0009). **Recommended** |
| `modelFile` | one of `artifact`/`modelFile` | — | `^[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.gguf$`, no `..` | Legacy (ADR 0008): GGUF file name inside the app's `Models` folder, used **without** hash verification. Not a path. Kept for backward compatibility and development smoke tests |
| `parallel` | no | 1 | 1–4 | llama-server `--parallel` slots |
| `startupTimeoutSeconds` | no | 120 | 5–600 | Time allowed for authenticated readiness before `failed` |
| `idleUnloadSeconds` | no | 900 | 0 or 60–86,400 | Stop the runtime after this long with no inference in progress; 0 never unloads |

Rules and behavior:

- Exactly one model stub must reference a `managed` provider. Its `model` value becomes the server `--alias`; `contextTokens × parallel` becomes `--ctx-size`, so each slot receives the stub's `contextTokens`. `minimumMemoryGB` is enforced as for `local`.
- Exactly one of `artifact` or `modelFile` must be set. With `artifact`, the model stub's `contextTokens` must not exceed the artifact's approved `contextTokens`, and its `minimumMemoryGB` must be at least the artifact's `minimumMemoryGB`. At launch the artifact's `runtimeTags` must include the bundled runtime tag, and the file must be verified, or the runtime refuses to start.
- The `Models` folder is `<Application Support>/<bundle id>/Models`. For the packaged, sandboxed app that is `~/Library/Containers/org.minimodell.agent/Data/Library/Application Support/org.minimodell.agent/Models/`. A symlink to a file outside the container is not readable by the sandboxed helper (verified). Use Settings → Models → Download or Import to place a verified artifact there.
- The runtime requires a packaged app built after `scripts/fetch-runtime.sh`. `swift run minimodell` has no bundled helper, so a `managed` model fails with "This build does not include the bundled local runtime."
- The runtime starts lazily on the first inference call of a task; startup time counts against `limits.timeoutSeconds`. A crash or failed readiness surfaces as a task error and a UI state. There is no automatic restart in the background and never a cloud fallback.
- Changing `artifact`, `modelFile`, `parallel`, `contextTokens` or `model` restarts the runtime at the next task. Removing every `managed` provider stops it at the next reload.

Example (`Config/bundled-runtime.example.json`):

```json
{"id": "bundled", "kind": "managed",
 "runtime": {"artifact": "qwen3-4b-instruct-2507-q4_k_m", "parallel": 1, "startupTimeoutSeconds": 120, "idleUnloadSeconds": 900}}
```

Legacy form, still accepted: `"runtime": {"modelFile": "SmolLM2-135M-Instruct-Q8_0.gguf"}`.

Migration: schema version stays `1`. Existing configurations are unchanged and still valid; `baseURL` became optional only for the new `managed` kind. Older app builds reject a policy that contains `"kind": "managed"` (unknown enum value), so do not push a managed provider through MDM to Macs running a build without this change. Forced managed policy may use `managed` like any other provider; users cannot add one to a forced policy.

## Model object

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Stable app catalog ID |
| `title` | yes | Display label |
| `providerID` | yes | Must reference a configured provider |
| `model` | yes | Nonempty exact alias sent to the provider |
| `minimumMemoryGB` | yes | Nonnegative total physical memory threshold; enforced for local models |
| `contextTokens` | yes | 2,048–131,072; must exceed output token limit |

`minimumMemoryGB` uses bytes divided by 1,073,741,824. It does not reserve memory or account for other applications. A cloud or LAN model is not subject to local model-memory eligibility. A stub has no file URL, checksum, quantization, template, license or runtime revision; for the bundled runtime those live in the model artifact the provider's `runtime.artifact` references (below). Display names (`title`, `displayName`) are presentation only; IDs are identity.

## Model catalog object (`modelCatalog`, optional)

Authoritative implementation: `Sources/LocalAgentCore/ModelCatalog.swift` (ADR 0009). The app has a built-in catalog (`catalogVersion` `2026-09-23.1`). Each field present in `modelCatalog` replaces the matching built-in value, and each absent field keeps it.

| Field | Required | Default | Meaning |
| --- | --- | --- | --- |
| `approvedHosts` | no | `["huggingface.co", "hf.co"]` | 1–16 lowercase DNS names. An artifact `sourceURL` and every download redirect must use one of these hosts or a subdomain of one. No wildcards |
| `allowDownloads` | no | `true` | `false`: artifacts can only be imported from a local file (still size- and hash-verified) |
| `artifacts` | no | built-in list | Replaces the built-in artifacts entirely: at most 32, with unique `id`s and unique `fileName`s (case-insensitive) |

### Artifact object

| Field | Required | Constraints | Meaning |
| --- | --- | --- | --- |
| `id` | yes | `^[A-Za-z0-9_.-]{1,64}$` | Stable identity referenced by `runtime.artifact` |
| `displayName` | yes | 1–80 characters | Presentation only |
| `sourceURL` | yes | HTTPS; no credentials, query string or fragment; approved host | Download location. Pin an immutable revision (for Hugging Face, `/resolve/<commit>/`, not `/resolve/main/`) |
| `fileName` | yes | plain `.gguf` name, no path | Name of the verified file in the `Models` folder |
| `sizeBytes` | yes | 1 byte–64 GiB | Exact size; checked before hashing and while downloading |
| `sha256` | yes | 64 lowercase hex characters | SHA-256 of the whole file |
| `quantization` | yes | nonempty | e.g. `Q4_K_M` |
| `license` | yes | nonempty (SPDX identifier) | License of the weights |
| `licenseURL` | no | HTTPS | Where the license text is |
| `chatTemplate` | yes | nonempty | Template identity and tool-call notes |
| `runtimeTags` | yes | nonempty list of `^[A-Za-z0-9._-]{1,32}$` | Bundled llama.cpp tags the artifact was checked with. The runtime refuses any other tag |
| `minimumMemoryGB` | yes | 1–512 | Minimum physical memory. A model stub may require more, never less |
| `contextTokens` | yes | 2,048–1,048,576 | Largest approved context. A model stub may use less, never more |

Built-in artifact: `qwen3-4b-instruct-2507-q4_k_m`, Qwen3-4B-Instruct-2507 Q4_K_M (Apache-2.0). The source is `bartowski/Qwen_Qwen3-4B-Instruct-2507-GGUF` at revision `ae44f08e…`: 2,497,280,736 bytes, SHA-256 `2fde00ce…bca4464e`, runtime `b11140`, 16 GB minimum memory, 8,192 context. This is a developer-preview default measured on one machine, not a support claim (see `docs/validation-results.md`).

Store behavior (`ModelStore.swift`):

- Downloads land in `Models/.partial/<id>.part`. An HTTP Range request resumes them after a network interruption.
- A download needs the remaining bytes plus 512 MiB free.
- A file is promoted to `Models/<fileName>` by an atomic rename, and only after its size and SHA-256 match.
- The verification record in `Models/.verified/<id>.json` ties the hash to the file's size, inode and modification time. A promoted file that changed is hashed again before use and refused if it no longer matches.
- Cancel removes the partial file. An unapproved redirect, an HTTP error, an oversized body, or a size or hash mismatch also discards it.
- Import copies the selected file into `.partial` and hashes the copy before promoting it.

Validation fails closed:

- A catalog with an invalid host, hash, size, URL or duplicate is rejected as a whole. The app does not fall back to the built-in catalog.
- A `runtime.artifact` missing from the effective catalog is rejected.
- A forced managed `PolicyJSON` replaces the whole configuration, catalog included, so users cannot add artifacts or hosts to it.

Example: an organization-approved catalog with downloads disabled and only one artifact allowed:

```json
"modelCatalog": {
  "approvedHosts": ["models.example.com"],
  "allowDownloads": false,
  "artifacts": [{
    "id": "org-qwen3-4b", "displayName": "Qwen3 4B (IT approved)",
    "sourceURL": "https://models.example.com/qwen3/ae44f08e/Qwen_Qwen3-4B-Instruct-2507-Q4_K_M.gguf",
    "fileName": "Qwen_Qwen3-4B-Instruct-2507-Q4_K_M.gguf", "sizeBytes": 2497280736,
    "sha256": "2fde00ce69dd4899c70d020845e2638353015bba0fdf161b3eb965f2bca4464e",
    "quantization": "Q4_K_M", "license": "Apache-2.0", "chatTemplate": "Embedded Qwen3 ChatML template",
    "runtimeTags": ["b11140"], "minimumMemoryGB": 16, "contextTokens": 8192
  }]
}
```

Migration for `modelCatalog`:

- Schema version stays `1`. Configurations without `modelCatalog` or `runtime.artifact` are unchanged and still valid.
- `runtime.modelFile` became optional, but exactly one of `artifact` or `modelFile` is still required.
- Older builds ignore the unknown `modelCatalog` key. They reject a `runtime` block without `modelFile`, so a policy that uses `artifact` fails closed on older builds.
- Separately provisioned, read-only shared model directories are not supported yet.

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

## Per-user preferences that are not policy

The command bar's global shortcut is stored in the app's `UserDefaults` under `commandBarHotkey` as text such as `option+space` (modifier names joined with `+`, then one key; at least one modifier). It is not part of `PolicyJSON` or `config.json`, grants no capability, and an invalid value falls back to ⌥Space. Administrators can preset it with an ordinary (non-forced or forced) preference in the `org.minimodell.agent` domain; the app re-registers when the preference changes.

## Validate and deploy

```sh
swift run minimodell-diagnostics --config Config/enterprise.example.json
swift run minimodell-diagnostics --config Config/bundled-runtime.example.json
swift run minimodell-diagnostics --config Config/lan-lmstudio.example.json
scripts/make-profile.py Config/enterprise.example.json build/minimodell.mobileconfig
plutil -lint build/minimodell.mobileconfig
```

The profile generator checks that input parses as JSON but does not run the Swift validator. Always validate first. Diagnostics is metadata-only and makes no network request unless `--probe-provider <id>` is given. That option lists model IDs from one provider's `/models` endpoint. Diagnostics cannot prove model quality, OAuth correctness or real MDM delivery.
