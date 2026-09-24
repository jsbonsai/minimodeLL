# Current project state

Last reviewed: 2026-09-23. Stage: **0.1.0 developer preview**. No production release has been published.

## Product and owner intent

The owner administers an existing LibreChat deployment and its MCP integrations. API inference spending motivates moving routine, small workplace tasks onto employee Macs. The intended product is open source, useful to other enterprises, and substantial enough to demonstrate native app development, local inference, protocol integration, policy, auditability, and deployment engineering.

The app name is minimodeLL. It must remain easy to rename. The standalone app comes first; optional Jamf and Kandji deployment/policy sit on top. Jamf is the initial live validation target, using the owner/coworker sandbox; Kandji is best-effort with no test environment. Explicit LiteLLM support remains valuable for approved cloud models. The baseline tools are Gmail, Google Calendar, Atlassian and Slack; Salesforce, Asana and GitHub are later candidates. No live company endpoint, OAuth registration, or credential has been provided in this repository.

## Capability matrix

| Area | Implemented now | Evidence | Gap before production |
| --- | --- | --- | --- |
| Native app | SwiftUI window, menu bar, settings, result display, stop control | Packaged launch and UI inspection | Accessibility, sleep/wake, lifecycle and multi-window tests |
| Branding | One bundled JSON source for display name/version/identity | Package/build succeeds | Identity migration strategy if forks rename deployed IDs |
| Local inference | Chat Completions requests to configured literal loopback address | Labeled synthetic HTTP fixture from sandboxed UI | Real model/tool-template qualification; bundled runtime |
| LiteLLM | Explicit HTTPS provider and gateway model alias | Compiles; config validator exercised | Live gateway authentication, payload compatibility and model tests |
| MCP | Official SDK 0.12.1, Streamable HTTP, approved-tool discovery/execution | Compiles; runner tests use fake tools | Actual four-service compatibility and malicious/slow transport tests |
| OAuth | Native browser delegate, SDK PKCE/discovery/refresh, Keychain token adapter | Compiles | Live registration/callback/refresh/logout and trust-boundary validation |
| Credentials | Keychain generic passwords, no synchronization requested | Code/build review | Stable Developer ID signing and persistence failure UX |
| Policy | Versioned Codable JSON; forced MDM policy replaces user config | Validator tests and generated profile lint | Actual enrolled-device forced preference behavior |
| Catalog | Approved provider/model stubs with RAM/context requirements | Validator and diagnostics | Verified artifacts, manifests, downloads, template hashes and licensing |
| Execution safeguards | Input/context/output/step/result/time limits; tool schemas and approvals | 16 tests across policy/runner/audit | Exact token counting, transport memory limits, pressure-aware admission |
| Audit | Metadata JSONL and OSLog, bounded local retention | Payload-shape and write-failure tests; fixture run | Richer provenance/outcome events and optional central export |
| Diagnostics | CLI policy validation, RAM/OS, eligible model IDs | Both examples pass on development Mac | Connectivity or performance qualification runner |
| Packaging | Ad-hoc sandboxed .app; DMG/PKG scripts | .app signature and launch verified | DMG/PKG install, Developer ID, notarization, clean-machine checks |
| Open source | Public GitHub repo, MIT, contributor/security docs, CI and eight work issues | Foundation and follow-up commits pushed; all 16 tests and packaging/management checks pass in hosted CI | Production release practices pending; green run linked from handoff |

## Actual local checkpoint

- Repository started with two PRDs and no implementation or Git history.
- A fresh Swift package now contains three products: reusable core, app, diagnostics.
- Initial development `.app` is generated at `build/minimodeLL.app`; it is ignored by Git.
- No runtime or GGUF is installed by the project. No real LLM inference has been benchmarked.
- The local fixture was started for one synthetic UI request and stopped afterward.
- The app may be open from the previous session. Inspect the local machine before restarting it; this is not a requirement for code work.
- User configuration/audit files created by the preview live outside the repository, in its sandbox container. Do not commit them.
- GitHub hosting/bootstrap status is tracked in `docs/handoff.md` and the latest session record.

## Known limitations and sharp edges

1. Local inference is an external server dependency. The app does not launch, unload, authenticate by default, or terminate that server. Configured bearer authentication is available but optional in the preview.
2. RAM eligibility checks total physical RAM only. They do not measure current availability, pressure, KV cache or swapping.
3. Context accounting is a conservative UTF-8-byte estimate of encoded messages and tools, plus output/framing allowance. It is not the model's tokenizer or rendered template.
4. MCP result limits apply after SDK buffering/decoding. Non-text or empty results fail rather than silently dropping content. Structured-content-only, image and resource responses are not supported.
5. Tool schema support is an explicit subset. Unsupported constraints reject discovery; a real company's schemas may therefore require compatibility work before first use.
6. OAuth token storage callbacks cannot throw through the SDK's `TokenStorage` protocol. Persistence failures currently emit a generic OSLog error, and load failures return no token. This needs explicit user-facing diagnosis and validation.
7. SDK cancellation and streaming behavior against unresponsive peers are not proven by fake-tool tests. TaskGroup deadlines rely on operations responding to cancellation/disconnect; they are not process-level hard deadlines.
8. App policy is sampled at task start. It does not retroactively stop an already accepted remote action when MDM policy changes.
9. The UI checks selected model ID and provider kind/URL after reloading policy, preventing an unnoticed destination switch on submission. It does not yet compare every model alias, credential, prompt, and tool policy field for a full policy revision review.
10. Configuration decoding ignores unknown JSON keys. The generator serializes policy but does not independently run Swift validation. Follow the documented validation-before-generation sequence.
11. Audit entries do not contain a policy hash, model artifact hash, latency, normalized failure code or explicit uncertain-write outcome. Local files are user-modifiable and not an immutable audit service.
12. Model and service examples are stubs. `minimumMemoryGB: 16` does not certify a model for a 16 GB machine; the alias `local-model` is not a chosen model.
13. The packaged sandbox and SwiftPM development execution use different Application Support locations. A successful `swift run` is not a sandbox test.
14. The current diagnostics reports `arm64` as a fixed target label. It is intended for the Apple Silicon scope and should use measured architecture if additional architectures are supported.
15. The schema exposes one configured tool set for a run, not yet task-specific tool selection or a model router. Large tool sets can exhaust the conservative context estimate before inference.

## Immediate next implementation

Follow the ordered backlog. The recommended first feature is a pinned, authenticated, sandbox-compatible bundled llama.cpp lifecycle, with failure/cleanup tests before connecting company accounts. Model artifact management follows it. A runtime revision and model must be selected and qualified rather than guessed from the historical PRD.
