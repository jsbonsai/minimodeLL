# Development validation — September 23, 2026

Environment: M1 Pro, 32 GB unified memory, macOS 15.7.7, Xcode 16.4, Swift 6.1.2.

- SwiftPM debug build succeeds.
- 15 deterministic tests pass, including cancellation before tool execution, duplicate call rejection and audit-write failure blocking.
- Local and enterprise example configurations pass the shared diagnostics validator.
- Generated MDM profile passes `plutil -lint`.
- Ad-hoc signed development app passes strict codesign verification and carries App Sandbox and outbound network entitlements.
- Packaged app launches; task window and configuration settings inspected through macOS accessibility and screenshot capture.
- A synthetic request completes from the packaged sandboxed UI against `scripts/mock-inference.py`. The response is explicitly labeled a fixture; no LLM, MCP server, OAuth account or company data was used.

The launch check found and fixed an app preference-domain initialization crash. Packaging checks found and fixed the SwiftPM resource placement for signed app bundles.

Not yet validated: model latency/quality/memory, actual remote LiteLLM or MCP services, OAuth across launches, real Jamf delivery, bundled inference runtime, notarization, DMG/PKG installation, other fleet hardware. These remain release gates, not implied by passing unit tests.

## Documentation/management continuation

The shared `scripts/mdm-readiness.sh` passed locally against the development app and enterprise example policy, and shell syntax validation passed. This is artifact/schema evidence only, not enrolled-device evidence. Kandji workflows were checked against official Custom Apps, Custom Profiles and Custom Scripts documentation; no tenant was available. A focused Jamf sandbox test is planned with the owner's coworker.

The GitHub bootstrap continuation added a host-independent fake model fixture and a separate memory admission test. `swift test` passed all 16 tests locally. The production starter RAM requirement remains unchanged. CI now includes the shared MDM readiness check, skips Markdown-only pushes/PRs and has a 15-minute job timeout. Hosted run results are recorded in the session completion record.

## Hosted GitHub CI

- Foundation commit `283ad43`: [initial run](https://github.com/jsbonsai/minimodeLL/actions/runs/35936009136) failed because fake inference fixtures inherited a 16 GB real-model RAM threshold. Five tests stopped at memory admission; dependency/application compilation succeeded.
- Corrected commit `3689e10`: [run 35936172136](https://github.com/jsbonsai/minimodeLL/actions/runs/35936172136) passed in 1m47s. All 16 tests, both example-policy checks, packaged app/signature verification, shared MDM readiness, profile generation and plist lint passed. This does not establish live Jamf/Kandji, OAuth, model quality or notarization.
- A nonblocking actions/checkout Node runtime deprecation annotation remains for future workflow maintenance.

## Brand asset integration

The feat/brand-assets packaged app built and passed strict codesign verification, then was restarted locally. The branded dark-mode workspace was visually inspected. App icon metadata and packaged resource identity were checked. Light appearance and active/off icon states were not separately exercised; no core/provider behavior was changed.

## Bundled runtime readiness slice (WORK-001, branch feat/runtime-lifecycle)

Environment: Apple M1 Pro (MacBookPro18,3), 32 GB, macOS 15.7.7 (24G720), Xcode 16.4, Swift 6.1.2. Runtime: official ggml-org/llama.cpp prebuilt `llama-b11140-bin-macos-arm64.tar.gz` (tag `b11140`, commit `dc9879cf6`, reports `version: 0.4.1-dev (build 11140)`), SHA-256 `ab2c33cd…cbece15`, MIT license. Smoke-test model: `bartowski/SmolLM2-135M-Instruct-GGUF` revision `09816acd5d99`, file `SmolLM2-135M-Instruct-Q8_0.gguf` (144,811,360 bytes, SHA-256 `5a139571…6bba83` matched the Hugging Face LFS hash), Apache-2.0. It was chosen only to exercise the runtime; it is **not** a candidate or qualified model and no quality claim is made. The model file was placed in the app container's `Models` folder and is not in the repository. The owner's container `config.json` was backed up, temporarily replaced with a `managed` provider, and restored afterwards.

Automated:

- `swift test`: 37 tests passed (16 existing + 21 new runtime/config tests using `FakeHost`/`FakeProcess`; no model or server started).
- Diagnostics passed for `Config/local.example.json`, `Config/enterprise.example.json`, the new `Config/bundled-runtime.example.json`, and the temporary smoke-test policy. `scripts/mdm-readiness.sh` passed with the runtime-embedded app.
- `scripts/fetch-runtime.sh`: download + size/SHA-256 verification + closure check completed in about 2 s. With a lock whose SHA-256 was altered (`RUNTIME_LOCK=…`), it failed with "checksum mismatch … refusing to extract" and left the verified vendor copy intact.
- `scripts/package-app.sh` with the runtime: `codesign --verify --strict --deep` valid. `llama-server` and `minimodell-runtime-guard` carry only `app-sandbox` + `inherit`; the guard has hardened runtime, the ad-hoc `llama-server` does not (see below). App entitlements: app-sandbox, network.client, network.server, files.user-selected.read-only.

Live, packaged ad-hoc-signed app, `build/minimodeLL.app/Contents/MacOS/minimodell --runtime-smoke-test` (sandboxed; `secinitd` logged "AppSandbox request successful"):

1. Without `com.apple.security.network.server`: failed "Could not reserve a loopback port."; kernel logged `Sandbox: minimodell deny(1) network-bind local:*:0`. Entitlement added.
2. With hardened runtime on the ad-hoc helper: the helper died at launch; crash report `Library not loaded: @rpath/libllama-server-impl.dylib … not valid for use in process: mapping process and mapped file (non-platform) have different Team IDs`. Ad-hoc builds now sign the helper without hardened runtime. **The Developer ID path (hardened runtime on, shared Team ID) is not validated.**
3. With a libproc listener-ownership check: failed verification; kernel logged `deny(1) process-info-pidfdinfo children [llama-server]`. Replaced by the missing-key/decoy-key/real-key challenge.
4. After those fixes: `ok: true`, startup 264–537 ms, synthetic inference 37–174 ms, non-empty reply (7–44 bytes; content intentionally not recorded), final state stopped, no runtime process left. The first-ever launch took ~23 s before readiness (one-time Metal/cache warm-up; not re-measured).
5. With `--hold 8`, inspected while running: process tree app → guard → llama-server; `sandbox_check` reported app, guard and server all sandboxed (the calling shell not); argv contained `--host 127.0.0.1 --port <random> … --offline --no-slots --log-disable` and no key; `lsof` showed a single listener `127.0.0.1:<port>`; `/health` 200, `/v1/models` 401 with no key and with a wrong key, `/v1/chat/completions` 401 without key; the same port on the Mac's LAN address refused the connection.
6. File confinement: pointing `modelFile` at a symlink in `Models` whose target was outside the container failed "The runtime exited during startup"; kernel logged `Sandbox: llama-server deny(1) file-read-data <outside path>`.
7. Orphan handling: before the guard existed, `kill -TERM` and `kill -KILL` of the app both left `llama-server` running with ppid 1 (cleaned up manually). With the guard, both cases stopped the server and the guard within about 1 s (re-run after the guard gained its own SIGTERM→SIGKILL escalation, same result). Standalone guard checks (unsandboxed dev build): a child ignoring SIGTERM was killed after 3 s (guard exit 137); a normal child exited on SIGTERM (143); a child exit status of 3 was mirrored; a relative server path was refused (64).
8. `CONFIGURATION=release scripts/package-app.sh` (the path DMG/PKG scripts use) embedded both helpers and passed strict deep verification; the release app's smoke test also returned `ok: true` (startup 534 ms, inference 38 ms).
9. Normal GUI launch via `open`, then `osascript quit`: app started and exited cleanly with no runtime processes (the runtime is lazy and was not started).

Not tested: the readiness indicator's appearance and a task submitted through the GUI with a `managed` model (no UI automation was available; the smoke test uses the same `ManagedInferenceClient` path but not the SwiftUI views); `willTerminate` quit while the runtime is running (unit-tested only); idle unload in the packaged app (unit-tested only); tool calling through the bundled runtime; real production-sized models, memory pressure or hung inference; SIGKILL of the guard itself; Developer ID signing, notarization, DMG/PKG with the runtime. Hosted CI passed on this branch: runs 35940996724 (`f1a0068`), 35941407084 and 35941441473 (`5604266`, PR #19), including runtime fetch, packaging and entitlement checks on `macos-15`.
