# ADR 0008: App-owned bundled llama-server runtime

Date: 2026-09-23. Status: Accepted for the readiness slice of WORK-001 (issue #1). Refines ADR 0003. Developer ID signing, notarization, source-built provenance and a qualified production model remain open.

## Context

ADR 0003 chose llama.cpp for local inference but left the app talking to an externally started `llama-server` (port 9931, no authentication, started by hand or Homebrew). That is unsuitable for employee Macs: nothing guarantees the server version, a different process can own the port, the endpoint is unauthenticated, memory is never released, and Homebrew cannot be assumed. The owner asked for "a small init / readiness sort of runtime" owned by the app.

Constraints: the packaged app runs in App Sandbox with Hardened Runtime; policy lives in `LocalAgentCore`; failures must be explicit (no cloud fallback); no prompts, responses or keys may be logged.

## Decision

1. **Helper process, not in-process.** Embed the pinned official `llama-server` prebuilt as a signed helper (`Contents/Helpers/llama-server`, dylibs in `Contents/Frameworks`, rpath rewritten to `@executable_path/../Frameworks` only). It reuses the OpenAI-compatible client already tested, isolates native crashes from the UI, and can be killed to release memory. An in-process engine remains a future option with its own ADR.
2. **Pinned, verified upstream binary.** `packaging/runtime.lock.json` pins tag `b11140` (commit `dc9879cf66ae…`), the asset URL, byte size and SHA-256. `scripts/fetch-runtime.sh` downloads only that asset over HTTPS, verifies size and hash *before* extraction, derives the `@rpath` closure from `llama-server` and fails if it differs from the lock or links non-system paths (e.g. Homebrew), checks arm64, and copies the MIT license into the bundle (`Contents/Resources/Licenses/llama.cpp.txt`). Binaries live in gitignored `vendor/` and are never committed. Packaging without the runtime still works (external-server mode).
3. **Sandbox inheritance.** The helper and guard are signed with only `com.apple.security.app-sandbox` + `com.apple.security.inherit` (`packaging/Helper.entitlements`). The app adds `com.apple.security.network.server`: without it the sandbox denies `network-bind` (observed live), and the inheriting child must listen on loopback.
4. **New `managed` provider kind.** A `managed` provider has a `runtime` block (`modelFile`, `parallel`, `startupTimeoutSeconds`, `idleUnloadSeconds`) and no `baseURL`/credential. Exactly one model stub may use it; its `model` becomes `--alias` and `contextTokens × parallel` becomes `--ctx-size` so each slot gets the policy context. `modelFile` is a plain `.gguf` file name inside `<Application Support>/<bundle id>/Models` (the sandbox container for the packaged app) — never a path. Existing `local` and `litellm` providers are unchanged and backward compatible.
5. **`RuntimeManager` actor owns the lifecycle.** States: `stopped → starting → ready`, `failed(reason)`, `stopping`. Per launch: a free ephemeral 127.0.0.1 port, a 256-bit random API key passed to the child only via the `LLAMA_API_KEY` environment variable (not argv, not persisted, not logged), an explicit environment (no inherited `LLAMA_ARG_*` overrides), `--offline --no-webui --no-slots --log-disable`, no built-in agent tools, and child stdout/stderr discarded. Readiness polls `/health` until the startup timeout, then verifies the answerer: the child must still be alive, `/v1/models` must return 401 without a key **and** with a random decoy key, 200 with the real key, list the expected alias, and report `n_ctx ≥ contextTokens`. Any failure terminates the child and enters `failed`.
6. **Leases, idle unload, crash detection, stop.** Each inference call takes a lease; the idle timer (default 900 s, 0 disables) only runs when no lease is held. A child exit while ready becomes `failed("…stopped unexpectedly (exit status N)")`; there is no background restart — the next user-submitted task starts a fresh process. Changed policy (model file, context, parallel, alias) restarts the runtime. `stop()` sends SIGTERM, then SIGKILL after a grace period. `NSApplication.willTerminate` calls a synchronous `terminateForQuit()`.
7. **Runtime guard.** `minimodell-runtime-guard` (a ~40-line Swift executable, `Sources/RuntimeGuard`) spawns the server, forwards SIGTERM/SIGINT/SIGHUP (escalating to SIGKILL after 3 s, shorter than the app grace period), and stops the server when the app process disappears (re-parenting detected by polling `getppid`), exiting with the server's status. The packaged app never runs the server unsupervised (`bundledHelperURL` requires the guard).
8. **No cloud fallback.** Any runtime failure surfaces as a task error and a UI state; the selected model/provider never changes automatically.

## Alternatives considered

- **libproc listener-ownership check** (`proc_pidfdinfo` on the child's sockets): implemented first, then removed — App Sandbox denies `process-info-pidfdinfo` for children (observed live). The key challenge (missing + wrong key → 401, right key → 200) replaces it: only a server that knows the per-launch secret can pass.
- **Unix domain socket** (`--host /path.sock`): avoids TCP port races entirely but `URLSession` cannot speak HTTP over it; would need a custom HTTP client. Future hardening option.
- **`--api-key` argv**: visible to every local user via `ps`. Rejected in favor of the environment.
- **`com.apple.security.cs.disable-library-validation`**: not allowed alongside `inherit`. Instead, ad-hoc builds sign the helper *without* hardened runtime (dyld otherwise rejects the ad-hoc dylibs: "different Team IDs", observed live). With a real `SIGNING_IDENTITY` all nested code shares a Team ID and the helper keeps hardened runtime — **not yet validated** (no Developer ID available in this session).
- **Building llama.cpp from source**: stronger provenance (static link, our own flags) but slower CI and a toolchain dependency. The pinned official prebuilt with hash verification is the first step; source builds are follow-up.

## Consequences

- The app can now listen on loopback. The server binds `127.0.0.1` only (verified: LAN address refused); every API route except `/health` requires the per-launch key.
- The per-launch key is readable by same-user processes that can inspect another process's environment. The key protects against other users and unauthenticated local clients, not against malware already running as the user.
- Startup time counts against the task time limit because the runtime starts lazily on the first inference call.
- Model files outside the container are unreadable by the sandboxed helper (observed: `deny file-read-data` for a symlink target outside the container). Importing a user-selected model needs security-scoped bookmarks or a copy into the container — WORK-002.
- `SIGKILL` of the app is handled by the guard; `SIGKILL` of the guard itself would still orphan the server (not tested).

## Validation

See `docs/validation-results.md` ("Bundled runtime readiness slice") and `docs/sessions/2026-09-23-runtime.md`. Unit tests cover startup, timeout, exit during startup, crash while ready, foreign/any-key servers, alias mismatch, idle unload, stop escalation, quit, policy change, cancellation and configuration validation with fakes. Live: the packaged, ad-hoc-signed, sandboxed app ran a synthetic prompt end to end through the bundled helper with a 135M-parameter smoke-test model.
