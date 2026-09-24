# ADR 0009: Verified model artifact manifest, model store, and first real model

Date: 2026-09-23. Status: Accepted for a trimmed slice of WORK-002 (issue #2). Builds on ADR 0008 (bundled runtime). Managed read-only shared artifacts, rollback, a signed catalog and benchmark approval (WORK-005) remain open.

## Context

ADR 0008 let the packaged app run its own pinned `llama-server`, but the model was a plain `modelFile` name that someone had to copy into the container by hand. Nothing checked the file's identity, so a truncated download, a wrong quantization or a swapped file would load (or crash) without warning. A new user also had no way to get a model from inside the app. Issue #2 asks for versioned artifacts, verified download and import, atomic promotion, cancellation, disk-space checks, deletion, and a catalog that ordinary config or MDM can change without rebuilding the app.

Constraints: policy lives in `LocalAgentCore` and fails closed; forced managed policy fully replaces the user configuration; nothing content-bearing is logged; the sandboxed helper can only read files inside the container (observed in ADR 0008).

## Decision

1. **Artifact manifest.** `ModelArtifact` (in `ModelCatalog.swift`) records `id` (stable identity), `displayName` (presentation only), `sourceURL`, `fileName`, `sizeBytes`, `sha256`, `quantization`, `license` (SPDX), `licenseURL`, `chatTemplate` (template identity and tool-call notes), `runtimeTags` (qualified llama.cpp tags), `minimumMemoryGB` and `contextTokens` (the largest context approved for it). `ModelCatalog` adds `schemaVersion`, `catalogVersion`, `approvedHosts` and `allowDownloads`.
2. **Where the catalog comes from.** The app has a built-in catalog (`ModelCatalog.builtIn`, version `2026-09-23.1`). A configuration can include a `modelCatalog` block. Its `artifacts` replace the built-in list, its `approvedHosts` replace the default hosts, and `allowDownloads: false` turns off downloads. Forced managed `PolicyJSON` replaces the whole user configuration, so a user can never add artifacts or hosts to a managed catalog. An invalid catalog fails validation; the app never falls back to the built-in one.
3. **Policy link.** A `managed` provider's `runtime` sets exactly one of `artifact` (a catalog ID) or the legacy `modelFile`. With `artifact`, validation requires the ID to exist in the effective catalog. The model stub's `contextTokens` must be ≤ the artifact's `contextTokens`, and its `minimumMemoryGB` must be ≥ the artifact's. `modelFile` still works for existing configs and smoke tests. It is documented as unverified.
4. **Sources.** `sourceURL` must be HTTPS with no credentials, query string or fragment, on an approved host (exact match or a subdomain; no wildcards). It should pin an immutable revision. The default hosts are `huggingface.co` and `hf.co`, because Hugging Face redirects to `*.hf.co` CDN hosts (observed: `us.aws.cdn.hf.co`). Redirects are followed only to HTTPS approved hosts, and the final response host is checked again.
5. **ModelStore actor.** Layout inside `<container>/Application Support/<bundle id>/Models`: `<fileName>` is the promoted, verified file; `.partial/<id>.part` is an in-progress download or import; `.verified/<id>.json` is the verification record. The record binds the artifact ID and SHA-256 to the file's size, inode and modification time.
   - **Download:** checks the catalog and host, then free space (remaining bytes + 512 MiB margin). It appends to the partial file with an HTTP `Range` request. Appending happens only when the server answers 206 with a `Content-Range` that starts at the partial file's size; a 200 restarts from zero. The body may not exceed `sizeBytes`. A network interruption keeps the partial file so the next attempt can resume. An unapproved redirect, an HTTP error or an oversized body discards it.
   - **Verify, then promote:** the partial file must match `sizeBytes` and then the streamed SHA-256. Only then is it `rename(2)`d into place (atomic within the volume) and the record written. A size or hash mismatch deletes the partial file. It is never resumed or promoted.
   - **Cancel:** removes the partial file and returns the status to the on-disk state.
   - **Import:** the user picks a file (security-scoped, `files.user-selected.read-only`). The store rejects a wrong size at once, copies the file into `.partial` (an APFS clone on the same volume), hashes the copy rather than the source (so a source changed after selection is not trusted), and promotes it.
   - **Delete:** removes the file, the record and any partial file. The app stops the runtime first when the policy's artifact is deleted.
   - **Use:** `verifiedURL(for:)` returns the path only when the record still matches the file. Otherwise it re-hashes (about 1 s for 2.5 GB on the M1 Pro) and fails closed on a mismatch.
6. **Runtime wiring.** `RuntimeManager.acquire(provider:model:artifact:)` requires the artifact to be the one the policy names. The bundled runtime tag must be in its `runtimeTags`, and `ModelStore.verifiedURL` must succeed. Only then does it launch `llama-server --model <verified path>`. The launch arguments now include `--jinja` explicitly. It is already the default in b11140, but the tool-call format depends on it.
7. **First approved model: Qwen3-4B-Instruct-2507, Q4_K_M.** Source: `bartowski/Qwen_Qwen3-4B-Instruct-2507-GGUF` at revision `ae44f08e1392f39c0e474af10c3ff8355c8b6688`, file `Qwen_Qwen3-4B-Instruct-2507-Q4_K_M.gguf`, 2,497,280,736 bytes, SHA-256 `2fde00ce69dd4899c70d020845e2638353015bba0fdf161b3eb965f2bca4464e`. The size and hash come from the Hugging Face LFS metadata and the `x-linked-etag`/`x-linked-size` headers, and match an independent `curl` + `shasum` run and the in-app download. Upstream weights are `Qwen/Qwen3-4B-Instruct-2507`, Apache-2.0. The GGUF embeds Qwen's ChatML Jinja template with `<tool_call>` JSON blocks, which llama-server `--jinja` parses into OpenAI `tool_calls`. It is approved for context 8192 (the measured setting) and a minimum of 16 GB memory. This is a **developer-preview default, not a support claim**: evidence is one machine and one runtime tag.

## Why this model

- A 4B model at Q4_K_M is about 2.5 GB on disk. Measured peak RSS of the sandboxed `llama-server` was 3,736 MiB at 8K context (3,678 MiB when run directly), which leaves room on a 16 GB Mac.
- The 2507 Instruct variant is **non-thinking**. It does not spend the 768-token output budget on `<think>` blocks, and it needs no `chat_template_kwargs` switches.
- Qwen3's tool-call format is the Hermes-style `<tool_call>` form that llama.cpp's Jinja path supports. The live synthetic tool round trip passed three times out of three through the real `TaskRunner` validation path.
- Apache-2.0 allows redistribution and commercial use. The license URL is recorded in the artifact.
- **Why bartowski's quantization:** Qwen publishes no official GGUF of the 2507 4B Instruct (`Qwen/Qwen3-4B-Instruct-2507-GGUF` does not exist), and `ggml-org` has only Q8_0 (4.3 GB). bartowski's llama.cpp imatrix quantizations are widely used and keep the upstream template. unsloth's `Qwen3-4B-Instruct-2507-GGUF` Q4_K_M (SHA-256 `3605803b…c67e597`, 2,497,281,120 bytes) was the close alternative. It was not chosen because it may carry unsloth template edits; this was not investigated further.

## Alternatives considered

- **Qwen3.5-4B (Apache-2.0, `unsloth/Qwen3.5-4B-GGUF` Q4_K_M, 2.74 GB):** newer, but it thinks by default, recommends a context of 128K or more to keep thinking quality, is multimodal (separate mmproj), and uses the qwen3_coder tool parser. It is worth re-evaluating in WORK-005 with thinking disabled.
- **IBM Granite 4.0 micro / h-micro (Apache-2.0):** a credible enterprise-oriented candidate. It was not measured this session.
- **Gemma 3n E2B/E4B:** released under the Gemma terms, which are not an OSI license, so they are less suitable as an open default.
- **Keep only `modelFile`:** it cannot tell a corrupt or swapped file from the approved one. Rejected.
- **Hash on every launch:** it adds about 1 s per start, and the record check covers files that have not changed. Kept as the fallback whenever the record does not match.
- **`URLSessionDownloadTask` with resume data:** its resume data is opaque, stored outside the store's control, and does not survive the app's own partial-file cleanup rules. A delegate-driven data task that writes straight to `.partial` keeps resume, size limits and host checks explicit.
- **Signed catalog:** it would let a remote catalog be trusted without MDM. It is deferred. The catalog is currently trusted because it comes from the app binary, the user's own config, or MDM-forced policy.

## Consequences

- A fresh user whose config points at `artifact: "qwen3-4b-instruct-2507-q4_k_m"` can open Settings → Models, press Download (about 58 s on this connection, including verification), and run tasks locally.
- A file is used only after its size and SHA-256 match. A corrupt file, including one tampered with after verification (tested live), is refused and the helper is never launched.
- Integrity is not quality. Benchmark and qualification approval stay separate (WORK-005). Changing the approved model means a catalog change plus new measurements in `docs/validation-results.md`.
- The same-user threat model from ADR 0008 still applies. Malware running as the user could replace the file and forge the record in the same container. Verification protects against corruption, partial downloads and accidental swaps, not against a compromised account.
- Separately provisioned, read-only shared model directories (for example `/Library/Application Support/...` placed by MDM) are **not** supported yet. The sandboxed helper cannot read outside the container, so they need a design (import by bookmark or copy) of their own.

## Validation

`Tests/LocalAgentCoreTests/ModelStoreTests.swift` (17 tests, fakes only) covers: the built-in catalog pinned and matching the runtime lock; catalog validation failing closed; artifact policy validation; a policy catalog replacing the built-in one without extension; legacy configs decoding; download verify-then-promote; hash mismatch; size mismatch and oversize; cancellation removing the partial file; resume after interruption; disk-space refusal; catalog, host and allowDownloads gates; import verification; tamper re-verification; delete; the runtime launching only verified artifacts; and the runtime tag gate. Live evidence is in `docs/validation-results.md` ("Verified model artifact and first real model") and `docs/sessions/2026-09-23-model-catalog.md`.
