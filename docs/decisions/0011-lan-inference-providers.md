# ADR 0011: LAN OpenAI-compatible inference providers

Date: 2026-09-23. Status: Accepted. Implemented on `feat/lan-inference` (WORK-016, issue #21). Extends [ADR 0003](0003-explicit-inference-providers.md); does not change [ADR 0008](0008-bundled-runtime-lifecycle.md).

## Context

The owner wants a small laptop to send inference to a larger Mac on the same network: LM Studio on an M2 Max, Ollama, or `llama-server`. He wants this for standalone use and, where an organization's policy permits it, for managed use.

Before this change the app had three provider kinds. `local` accepts only literal loopback HTTP. `litellm` accepts HTTPS to any host and is labeled as cloud. `managed` is the app-owned bundled runtime. A LAN server usually listens on plain HTTP at a private address, so it fits none of them:

- Loosening `local` would weaken the "this Mac only" guarantee that its label and memory check rely on.
- Using `litellm` requires TLS, which most LAN servers don't have, and labels the destination as cloud, which is wrong.

A LAN destination is a different trust boundary from both. The request and every tool result leave this Mac, but they stay on a network the user or organization controls. If the connection is plain HTTP, anyone on that network segment can read or change the traffic.

## Decision

1. **New provider kind `lan`.** It has a `baseURL`, an optional `credentialAccount`, an optional `allowInsecureTransport`, and no `runtime` block. `local`, `litellm` and `managed` are unchanged.
2. **Host restriction, enforced in `LocalAgentCore` (`LANHost`).** A `lan` URL's host must be one of:
   - a literal private IPv4 address in 10/8, 172.16/12 or 192.168/16 (RFC 1918), or 169.254/16 (link-local). 169.254.169.254 is excluded because it is the cloud instance-metadata address and never an inference server.
   - a literal IPv6 address in fc00::/7 (unique local) or fe80::/10 (link-local, with an optional alphanumeric `%zone`).
   - an mDNS name ending in `.local` (RFC 6762), with LDH labels.

   Everything else is rejected, whether the URL uses HTTP or HTTPS:
   - public addresses, and loopback (use `local` instead)
   - CGNAT 100.64/10, multicast, unspecified addresses, IPv4-mapped IPv6
   - non-canonical IPv4 spellings (`3232235777`, `0xC0.0xA8.1.1`, `192.168.001.001`)
   - `localhost`, and every DNS name that does not end in `.local` (`lmstudio`, `lmstudio.lan`, `*.home.arpa`, public names)

   A hostname that is not `.local` could resolve to a public address, so accepting one would make the "LAN" label a claim the app can't check.
3. **Transport.** HTTPS is always allowed. Plain HTTP is allowed only when the provider sets `"allowInsecureTransport": true`. Setting the flag on an HTTPS LAN URL, or on any other provider kind, fails validation. Keeping the flag unambiguous matters more than keeping it lenient. The existing URL rules still apply: no user info, query string or fragment, and redirects are refused.
4. **Request-time checks and DNS rebinding.** `ProviderSpec.verifiedBaseURL()` runs before every inference request and every probe. It validates the endpoint again, and for a `.local` name it resolves the name with `getaddrinfo`, which uses mDNS. Every address in the answer must be a LAN address. An empty answer, or one public or loopback address, refuses the request.
5. **Residual risk.** URLSession resolves the name again when it connects, so there is a small time-of-check/time-of-use window. An attacker who can answer mDNS on the local link could swap the address between the two lookups. Such an attacker is already on the LAN and can intercept plain HTTP anyway, so this check limits accidental or public-DNS leakage. It does not defend against a hostile local network. The ways to reduce that risk are HTTPS, a literal IP address, or both. Pinning the connection to the checked address would require a custom HTTP stack, because URLSession does not allow overriding `Host` for plain HTTP. That work is deferred.
6. **Credential.** The optional bearer token comes from Keychain through `credentialAccount`, the same path LiteLLM uses. LM Studio and `llama-server` API keys work this way. If a `credentialAccount` is configured and no token is saved, the request fails. The token is never logged.
7. **Policy.** There is no new top-level switch. A forced managed `PolicyJSON` already replaces the whole configuration, and users can't add providers to it. That means a LAN provider exists under management only if the administrator lists one, and the default under managed policy is "forbidden unless listed", as the issue asks. A separate `allowLANProviders` flag would be a second source of truth that could disagree with the provider list. An administrator who doesn't want LAN inference lists no `lan` provider.

   Unknown `kind` values fail to decode, so older builds reject a policy that contains `lan`, and invalid forced policy blocks requests. Roll the app out before the policy.
8. **Destination labeling.** `ProviderSpec.destination` returns one of `thisMac`, `lan(host, encrypted)` or `cloud`. The task window shows the label before submission:
   - `LAN · TLS · your request and tool results are sent to <host>`
   - `LAN · unencrypted · your request and tool results are sent to <host> in plain text`

   The `local`, `managed` and `litellm` labels are unchanged. `lan` is not "on device", so the physical-memory eligibility gate does not apply, as for cloud.
9. **Test connection.** `ProviderProbe.listModels(provider:)` sends `GET <baseURL>/models` under the same endpoint rules, credential and redirect refusal as inference. It caps the response at 64 KiB and returns at most 100 printable model IDs. It is exposed in three places:
   - `minimodell-diagnostics --probe-provider <id>`: unsandboxed, and the only diagnostics option that uses the network.
   - `minimodell --probe-provider <id>`: runs inside the packaged app's sandbox against the resolved policy.
   - `AppState.testConnection(providerID:)`: for the Settings UI that comes later.

   None of them log or print response bodies.
10. **Packaging.** The Info.plist already had `NSAllowsLocalNetworking`. It now also has `NSLocalNetworkUsageDescription`, which supplies the text of the macOS 15 Local Network privacy prompt.

## Alternatives considered

- **Extend `local` to private addresses.** Rejected. `local` means "this Mac": its label, its memory gate, and the loopback-only probe in `RuntimeHost` all assume that.
- **Use `litellm` with an HTTP exception.** Rejected. The label would say cloud, and allowing HTTP to arbitrary hosts weakens the rule that remote inference requires HTTPS.
- **Accept any hostname and check resolution at request time.** Rejected for now. Split-horizon DNS and DNS rebinding make the check weaker than a syntactic `.local` rule, and the label could not be verified when the configuration is validated. A LAN server with a real certificate under a public DNS name can use `litellm`, which is labeled as cloud.
- **Accept `.home.arpa` (RFC 8375).** Deferred. Unicast DNS from a home router has the same rebinding profile as ordinary DNS. It can be added later together with resolution checks if needed.
- **Top-level `allowLANProviders`.** Rejected, as explained in decision 7.

## Consequences

- Plain-HTTP LAN inference is possible, and every configuration that uses it is explicit about it (`allowInsecureTransport`) and labeled before submission.
- Prompts and tool results can leave this Mac without going to a cloud gateway. Users and administrators must still decide whether the LAN host is trusted. The app does not authenticate the server beyond TLS, when TLS is used.
- There is still no automatic fallback between providers.
- The shared inference client (`CompatibleInferenceClient`) now takes the provider instead of a local/remote boolean, so every configured kind goes through `validateProviderEndpoint`.

## Validation

- Unit tests (`LANProviderTests.swift`) cover:
  - host classification: accepted and rejected sets
  - HTTP/flag rules
  - rejection of credentials, query strings and fragments
  - the flag on other kinds
  - rejection of unknown kinds
  - resolved-address checks, including a mixed private/public answer
  - request-time rejection before any network use
  - model-list parsing and caps
  - destination labels
  - validation of the example configuration
- A probe against a scratch fixture HTTP server bound to this Mac's LAN IP (192.168.1.87) was run from diagnostics (unsandboxed) and from the packaged app (sandboxed). It covered the literal IP, the Mac's own `.local` name, redirect refusal, and an unresolvable `.local` name. Evidence is in [the session record](../sessions/2026-09-23-lan-inference.md).
- **Not yet tested:**
  - a real LM Studio, Ollama or `llama-server` on another Mac, including chat completions with tool calls
  - a Keychain bearer token end to end against a LAN server
  - HTTPS with a private CA
  - the macOS 15 Local Network privacy prompt for a second host (probing this Mac's own address may not trigger it)
  - IPv6 LAN hosts on a real network

  The owner's M2 Max check is the acceptance gate for issue #21.
