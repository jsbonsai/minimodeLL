# 2026-09-23: LAN OpenAI-compatible inference providers (WORK-016, issue #21)

Branch `feat/lan-inference`, based on `main` at `15163e9`. This is one of several parallel streams. The coordinator integrates `docs/handoff.md`, `docs/project-state.md`, `docs/backlog.md`, `CHANGELOG.md`, `docs/sessions/README.md` and `docs/validation-results.md`; this stream did not edit them. Suggested text for each is at the end of this record.

## Goal

The owner wants to use an OpenAI-compatible server on his LAN from a small Mac, both standalone and, where policy permits, under management. The server could be LM Studio on an M2 Max, Ollama, or `llama-server`. Before this change there were three provider kinds: `local` (literal loopback HTTP only), `litellm` (HTTPS, labeled cloud) and `managed` (bundled runtime). A typical LAN server listens on plain HTTP at a private address, so none of the three fits.

## Findings before the change

- `CompatibleInferenceClient` stored a single `local: Bool`: `local` and `managed` were `true`, `litellm` was `false`. It then called `validateEndpoint(url, local:)`. A new kind therefore had to change the client as well as validation.
- `ProviderSpec.Kind.isOnDevice` was `self != .litellm`. A new kind added without changing it would have been treated as on-device, so the physical-memory gate would have applied to a remote server.
- The destination label was a ternary in the view (`kind == .litellm ? cloud : local`). A LAN provider would have been labeled "Local inference", which is misleading.
- The Info.plist already declared `NSAppTransportSecurity.NSAllowsLocalNetworking = true`, so ATS does not block HTTP to private IPs or `.local` names. There was no `NSLocalNetworkUsageDescription` for the macOS 15 Local Network prompt.
- The forced managed `PolicyJSON` is already a complete replacement. A LAN provider can exist under management only if the administrator lists one.

## Changes

Core (`LocalAgentCore`):

- `ProviderSpec.Kind.lan` and `ProviderSpec.allowInsecureTransport: Bool?`. The new field is optional and encodes as absent when nil, so existing configurations are unchanged.
- `LANProvider.swift` (new) contains:
  - `LANHost.classify`: strict dotted-quad IPv4 parsing, then the RFC 1918 and 169.254/16 ranges minus 169.254.169.254; IPv6 through `inet_pton`, then fc00::/7 and fe80::/10, with a `%zone` accepted only on link-local addresses; `*.local` names with LDH labels.
  - `LANHost.checkResolved` and `LANHost.resolve` (`getaddrinfo`, run off the cooperative pool): every resolved address must be a LAN address.
  - `InferenceDestination` (`thisMac`, `lan(host, encrypted)`, `cloud`), with a `label` and a stable `code`.
  - `ProviderSpec.destination` and `ProviderSpec.verifiedBaseURL()`, which validates again and re-resolves `.local` names before every request.
  - `ProviderCredential.bearer`: the Keychain token, shared by inference and the probe.
  - `ProviderProbe.listModels`: `GET <baseURL>/models` with the same rules, a 64 KiB cap and at most 100 printable IDs.
- `Configuration.swift`:
  - `validateProviderEndpoint(provider)` and `validateLANEndpoint(url, allowInsecureTransport:)`.
  - `allowInsecureTransport: true` is rejected on non-`lan` kinds and on an `https` LAN URL.
  - `isOnDevice` is now `local || managed`.
- `Inference.swift`: `CompatibleInferenceClient` stores either a configured provider or the runtime endpoint. A configured provider goes through `verifiedBaseURL()` before each request, and the runtime endpoint keeps the loopback check.

App (`MinimodeLL`), kept to a minimum because a separate agent is redesigning the visuals:

- `AppState` gains `destination`, `destinationLabel`, `destinationSymbol`, and `testConnection(providerID:)` with `probeNotice` and `probedModelIDs`. The last three are not wired to any view yet.
- `MinimodeLLApp.swift`: the ternary label becomes `Label(state.destinationLabel, systemImage: state.destinationSymbol)`, and one dispatch line was added for `--probe-provider`.
- `ProviderProbeCommand.swift` (new): `minimodell --probe-provider <id>`, the sandboxed connection test against the resolved policy.

Diagnostics:

- `--probe-provider <id>` is the only option that uses the network. Its result has `reachable` and `modelIDs`, and the tool exits 2 when the provider is unreachable.
- The output now includes `providerDestinations` (provider ID mapped to `this-mac`, `lan-tls`, `lan-unencrypted` or `cloud`).
- Argument parsing now accepts `--config` and `--probe-provider` in any order.

Packaging: the Info.plist now includes `NSLocalNetworkUsageDescription`, whose text is built from the brand display name.

Configuration and CI: added `Config/lan-lmstudio.example.json`, with a `192.168.1.50:1234` placeholder, `allowInsecureTransport: true` and `credentialAccount: lan.lmstudio`. JSON has no comments, so the explanation lives in the configuration reference. CI now validates four example configurations.

Tests: `Tests/LocalAgentCoreTests/LANProviderTests.swift` has 15 tests. Two of them are parameterized, over 15 accepted hosts and 39 rejected hosts.

Documentation:

- ADR 0011, and a new row in the decisions index.
- `configuration-reference.md`: provider table, a LAN section, migration notes, and the diagnostics note.
- `architecture.md`: the diagram and a LAN section.
- `code-map.md`.
- `CLAUDE.md` (policy line) and `README.md` (one bullet).
- `site/config.json`: renders ADR 0011.

## Decisions (see ADR 0011)

- **A new `lan` kind** rather than loosening `local` or `litellm`: each existing kind's label and checks depend on what it means.
- **Hosts must be a literal private address or `.local`, over both HTTP and HTTPS.** A server with a public DNS name and a real certificate can use `litellm`, which is labeled cloud. `.home.arpa` was deferred.
- **HTTP requires `allowInsecureTransport: true`.** The flag is rejected wherever it would mean nothing, so a configuration can't carry a misleading setting.
- **Request-time mDNS resolution check.** A time-of-check/time-of-use window remains. The residual risk only applies to an attacker already on the local link; it is documented, not solved.
- **No top-level `allowLANProviders` switch.** A forced policy replaces the whole configuration, so a provider that isn't listed doesn't exist, and a second switch could disagree with the provider list.
- **LAN is not on-device.** The memory gate is skipped, as it is for cloud.
- **Label wording:** `LAN · TLS · your request and tool results are sent to <host>` and `LAN · unencrypted · … in plain text`. The `local`, `managed` and `litellm` labels are unchanged.

## Validation actually run (this Mac: macOS 15 / Darwin 24.6, Apple Silicon, Xcode toolchain, Swift 6.1)

| Check | Result |
| --- | --- |
| `swift build` | Passed |
| `swift test` (full suite) | `✔ Test run with 71 tests passed` |
| `swift test --filter LANProviderTests` | 15 tests passed |
| `swift run minimodell-diagnostics --config` on each of the four examples | Exit 0 for `local`, `enterprise`, `bundled-runtime` and `lan-lmstudio`. `providerDestinations` was `this-mac`, `cloud`+`this-mac`, `this-mac` and `lan-unencrypted`, and `lan-approved` appeared in `eligibleModelIDs` |
| `scripts/make-profile.py Config/lan-lmstudio.example.json …` + `plutil -lint` | OK |
| `scripts/package-app.sh` (no runtime fetched in this worktree) + `codesign --verify --strict build/minimodeLL.app` | Passed. `plutil -p` shows `NSLocalNetworkUsageDescription` and `NSAllowsLocalNetworking` |
| Site: `site/build.py` + `site/check.py` (Python-Markdown from the hash-pinned lock, in a scratch venv) | 29 documentation pages built, 31 pages checked, 0 problems. The `#lan-providers-kind-lan` anchor exists |

The unsandboxed diagnostics probe ran against a scratch Python fixture that was not committed. The fixture served `/v1/models` with two IDs, a 302 on `/redirect/...`, and an optional bearer check. It was bound to this Mac's LAN IP 192.168.1.87:

| Config | Result |
| --- | --- |
| `http://192.168.1.87:9942/v1`, `allowInsecureTransport` | `reachable: true`, `["fixture-model-a","fixture-model-b"]`, exit 0 |
| `http://MacBook-Pro.local:9942/v1` (this Mac's own mDNS name) | reachable, same IDs, exit 0. The resolved answer passed the all-LAN check |
| `http://192.168.1.87:9942/redirect/v1` | `Model list request failed (HTTP 302)`: redirect refused, exit 2 |
| `http://no-such-host-7f3a.local:9942/v1` | `The LAN host name did not resolve.`, exit 2 |
| `http://example.com:9942/v1` | Configuration validation failed, exit 1 |
| `http://192.168.1.87:9942/v1` without `allowInsecureTransport` | Configuration validation failed, exit 1 |
| Fixture that requires a key, config without `credentialAccount` | `HTTP 401`, exit 2. The error contains no body text |

The same probes ran from the packaged app inside its sandbox (`build/minimodeLL.app/Contents/MacOS/minimodell --probe-provider lan-lmstudio`). The container `config.json` was backed up first, and after the run `cmp` confirmed it was restored byte-identical. Results: the IP and `.local` probes succeeded with `ok: true` and both IDs; the redirect probe returned HTTP 302 and exit 1; the unresolvable `.local` probe failed with exit 1. So the sandbox plus ATS permit HTTP to a private IP and to a `.local` name, and the mDNS lookup works inside the sandbox.

Packaged app UI launch: `pkill -x minimodell`, then the container config was switched to the LAN configuration and the app opened. The process was alive after 6 s. It was then quit, and the config restored and confirmed identical. The destination label was **not** seen: a `screencapture` produced a blank desktop because this session has no Screen Recording permission, and the image was deleted. `osascript` "System Events" was deliberately avoided. Nothing was left running: the fixtures were killed and no `minimodell` process remained.

## Not tested

- A real LM Studio, Ollama or `llama-server` on another machine. The owner's M2 Max was not available. This is the acceptance gate for #21.
- Chat completions (POST) to a LAN host, with or without tool calls. Only `GET /models` was exercised over the network. The POST path shares `verifiedBaseURL()` with the probe; unit tests prove it refuses invalid providers before any network use.
- A bearer token end to end against a LAN server. A test Keychain item created with `security add-generic-password -A` still triggered a SecurityAgent access prompt when the unsigned SwiftPM diagnostics binary read it, so that attempt was aborted, the process killed, and the item deleted. The Keychain read path is the one LiteLLM already uses.
- The macOS 15 Local Network privacy prompt for a *different* host. Connecting to this Mac's own LAN address may be exempt, and no prompt appeared. Whether the prompt appears and what denying it does are unverified.
- HTTPS to a LAN host with a private or self-signed CA. URLSession's default trust will reject self-signed certificates; the workaround is to install the CA in the System keychain. No custom trust override was added.
- IPv6 ULA and link-local hosts on a real network. They are covered only by unit tests.
- Visual check of the new label in the task window.
- CI on this branch (see the PR).

## Remaining work and suggestions

1. The owner runs the live check against LM Studio on the M2 Max:
   - Enable "Serve on local network", and optionally require an API key.
   - Copy `Config/lan-lmstudio.example.json` and set the IP.
   - Run `minimodell --probe-provider lan-lmstudio` and put a returned ID in the stub's `model`.
   - Run a synthetic task, then a tool task. Record the results in `docs/validation-results.md`.
2. A Settings UI "Test connection" button bound to `AppState.testConnection(providerID:)`, `probeNotice` and `probedModelIDs`. This belongs to the UI redesign stream.
3. Optionally, the approval sheet could say where the tool result goes ("The result will be sent to <host>") for `lan` and `cloud` destinations. That would be a one-line view change, left to the UI stream.
4. Optionally, pin the connection to the checked address to close the rebinding window. That needs a custom HTTP/1.1 client over `NWConnection`, or TLS to a literal IP.
5. `.home.arpa` support, if the owner's network uses it.

## Suggested text for shared docs (coordinator)

- **CHANGELOG (Unreleased → Added):** "`lan` inference provider kind (ADR 0011): OpenAI-compatible servers on private IPv4/IPv6 addresses or `.local` names (LM Studio, Ollama, llama-server). HTTPS, or plain HTTP only with `allowInsecureTransport: true`. `.local` names are re-resolved and checked before every request. The destination label shows `LAN · TLS` or `LAN · unencrypted` before submission. There is a connection test (`minimodell-diagnostics --probe-provider <id>`, `minimodell --probe-provider <id>`) and an optional Keychain bearer token. The example is `Config/lan-lmstudio.example.json`. The Info.plist adds `NSLocalNetworkUsageDescription`."
- **project-state.md:** "LAN inference (`lan` provider) is implemented and unit-tested. A `/models` probe was verified against a fixture on this Mac's LAN IP and `.local` name, both unsandboxed and from the sandboxed packaged app. It has not been validated against a real LM Studio, Ollama or llama-server on another host, and chat completions over LAN have not been exercised live."
- **backlog.md:** WORK-016 status → "Implemented (PR open); live M2 Max/LM Studio validation pending". Follow-ups: a Test-connection button in the Settings redesign; approval-sheet destination line; optional address pinning.
- **handoff.md next action:** "Owner: live-validate WORK-016 against LM Studio on the M2 Max (steps in docs/sessions/2026-09-23-lan-inference.md → Remaining work 1)."
- **validation-results.md:** copy the two probe tables above with the environment line, and state explicitly that the live LAN server, POST completions, bearer token, and the Local Network prompt were not tested.
- **sessions/README.md:** add a row: `2026-09-23-lan-inference.md`: WORK-016 LAN providers, ADR 0011.
