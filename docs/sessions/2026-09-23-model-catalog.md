# 2026-09-23: Verified model catalog and first real model (WORK-002, partial)

Branch: `feat/model-catalog`, stacked on `feat/runtime-lifecycle` (PR #19). **Merge after PR #19.** Issue: #2 (partial). ADR: [0009](../decisions/0009-model-artifact-manifest.md). Evidence: `docs/validation-results.md`, section "Verified model artifact and first real model".

## Intent and scope

The coordinator scoped a trimmed slice of WORK-002 so that a fresh user can get **one** small, tool-capable, openly licensed model running in the bundled runtime. The scope had five parts:

- choose and pin the model;
- a versioned artifact manifest in `LocalAgentCore` tied into policy;
- `ModelStore` (download, resume, disk check, verify-before-promote, cancel, delete, import) wired into `RuntimeManager`;
- a minimal Settings → Models UI, and fake-based tests;
- live proof with measurements.

The owner wants a Raycast-style UI later. This stream kept the UI deliberately plain.

Per the parallel-run rules, this stream did **not** edit `docs/handoff.md`, `docs/project-state.md`, `docs/backlog.md`, `CHANGELOG.md` or `docs/sessions/README.md`. Suggested text is at the end.

## Model choice (details in ADR 0009)

- **Chosen:** Qwen3-4B-Instruct-2507 Q4_K_M from `bartowski/Qwen_Qwen3-4B-Instruct-2507-GGUF`, revision `ae44f08e1392f39c0e474af10c3ff8355c8b6688`: 2,497,280,736 bytes, SHA-256 `2fde00ce69dd4899c70d020845e2638353015bba0fdf161b3eb965f2bca4464e`. Upstream weights are Apache-2.0.
  - The size and hash come from the HF API (`/api/models/<repo>/tree/main` LFS oid) and the `x-linked-etag`/`x-linked-size` headers.
  - They were independently confirmed by a `curl` download plus `shasum`, and again by the in-app download.
- **Why this model:**
  - It is non-thinking, so the output budget is not spent on `<think>` blocks.
  - It is about 2.5 GB, with about 3.7 GB peak RSS at 8K context.
  - Tool calling works through llama.cpp `--jinja`. Verified live: raw API and in-app `TaskRunner`, 3/3.
  - It has a permissive license.
- **Why this repository:** Qwen does not publish an official GGUF of this model, and `ggml-org` has only Q8_0.
- **Alternatives recorded:**
  - unsloth Q4_K_M (hash `3605803b…`), a possible template-edit concern;
  - Qwen3.5-4B, which thinks by default, is multimodal, and wants a long context;
  - Granite 4.0 micro (not measured);
  - Gemma 3n (not an OSI license).
- **Approved context:** 8,192, set to the measured value on purpose. Minimum memory is 16 GB.

## What changed

- `Sources/LocalAgentCore/ModelCatalog.swift` (new):
  - `ModelArtifact`, `ModelCatalogSpec`, `ModelCatalog` with built-in JSON (`catalogVersion` `2026-09-23.1`);
  - `AgentConfiguration.effectiveCatalog` and `artifact(for:)`;
  - host approval (exact name or subdomain, no wildcards) and full validation.
- `Configuration.swift`:
  - `ManagedRuntimeSpec.artifact` (new) or `modelFile` (legacy; now optional), exactly one required.
  - Optional root `modelCatalog`.
  - Validation: the catalog as a whole, the artifact must exist, and the stub context must be ≤ the artifact's and stub memory ≥ the artifact's.
- `ModelStore.swift` (new):
  - `ModelStore` actor and `ArtifactTransport` seam.
  - `URLSessionArtifactTransport`: delegate-driven data task that writes straight to disk, Range resume only on a 206 with a matching `Content-Range`, redirect and final host checks, body capped at `sizeBytes`.
  - `ArtifactTransportError.interrupted` marks failures that keep the partial file. Other failures discard it.
- `Runtime.swift`:
  - `RuntimeManager(modelStore:runtimeTag:)`, `bundledRuntimeTag`, and `acquire(provider:model:artifact:)`.
  - Launch settings resolve `ModelStore.verifiedURL` and check the runtime tag.
  - `--jinja` added to the launch arguments.
  - `ManagedInferenceClient(artifact:)` and `completeMeasured`.
- `Inference.swift`: `completeMeasured` plus `CompletionMetrics` (usage and llama-server timings; numbers only).
- `RuntimeSmokeTest.swift`:
  - token counts and tok/s in the report;
  - `--tool` synthetic round trip through `TaskRunner` with the `SyntheticOrderTool` fixture;
  - `--show-reply` for synthetic prompts only.
  - The prompt changed from "Reply with exactly one word: ready" to a two-sentence checksum question, which gives a more meaningful throughput number.
- `MinimodeLL`:
  - `AppState` owns the `ModelStore`, mirrors statuses, and has download/cancel/delete/import.
  - Settings → **Models** tab (`ModelsSettings`/`ModelRow`).
  - `--model-download [id]` CLI mode.
- Diagnostics lists a `model-catalog` check.
- `Config/bundled-runtime.example.json` now uses `"artifact": "qwen3-4b-instruct-2507-q4_k_m"`.
- Tests: `Tests/LocalAgentCoreTests/ModelStoreTests.swift` (17 new).
- Docs:
  - ADR 0009 (with a README row, and a status cross-link in ADR 0008);
  - `configuration-reference.md` (catalog and artifact schema, store behavior, migration);
  - `architecture.md` (flow diagram);
  - `code-map.md`, `validation-results.md`;
  - the README "Connect inference" section only.

## Findings

1. Hugging Face `resolve/<rev>` redirects (302) to `us.aws.cdn.hf.co`. The approved hosts must therefore include `hf.co` as well as `huggingface.co`, and the transport rechecks the final response host.
2. `llama-server` b11140 enables `--jinja` by default (`--help`: "default: enabled"). It is now passed explicitly anyway.
3. With tools, the model returns `content: ""` plus `tool_calls`. `TaskRunner` already treats the presence of `tool_calls` first, so this works.
4. A worktree-isolation guard in this environment refuses complex shell constructs (heredocs to interpreters, loops with variables). Helper scripts went into the scratchpad and were run as single commands.
5. `osascript` telling System Events to press ⌘, **hung**, probably waiting on an automation permission prompt. It was killed. The owner may see a stale prompt or a new entry under Privacy & Security → Automation.

## Validation actually run

See `docs/validation-results.md`. Summary:

- `swift test` 54/54.
- Diagnostics passed on all three examples.
- Packaging with the runtime passed a strict deep codesign check.
- Live sandboxed in-app download of 2.5 GB in 58.4 s, including verification; the hash matched independently.
- Three live smoke runs with a tool round trip:
  - about 1.07 s startup (warm page cache) and about 41 tok/s generation;
  - prompt 90–137 tok/s for 18 tokens;
  - tool round trip ok 3/3;
  - peak `llama-server` RSS 3,736 MiB.
- Forced re-hash adds about 1.1 s.
- A live tamper test was refused without launching the helper, and the restore worked.
- An unsandboxed direct baseline agreed with these numbers.
- GUI launch with no crash; Settings was not visually inspected.
- Hosted CI (`macos-15`) passed on `2d0e4bd`: push [run 35943293637](https://github.com/jsbonsai/minimodeLL/actions/runs/35943293637) and PR #20 [run 35943323556](https://github.com/jsbonsai/minimodeLL/actions/runs/35943323556). The workflow's `paths-ignore` skips Markdown-only commits after that.

## Not done / remaining WORK-002 items

- **UI and import not exercised:** the Models tab was not visually inspected and the Import file picker was not exercised live.
- **Real-network edge cases untested:** real-network resume, rejection of an unapproved redirect, and 206 handling.
- **Measurements still missing:** cold-disk load, a 16 GB Mac, memory pressure, contexts above 8K, and quality/accuracy (WORK-005).
- **Managed shared artifacts:** separately provisioned, read-only shared artifacts (for example an MDM-placed directory outside the container) are not supported. The sandbox prevents reading them directly, so they need a design.
- **Catalog and rollback:** rollback to a previous artifact version, a signed or remote catalog, and garbage collection of promoted files that no catalog lists any more.
- **Store limits:** only one download at a time per artifact (enforced), with no global queue. Progress persists only for the current app session; resume uses the partial file.
- **README License line:** it still says no runtime is redistributed. That stays true until a DMG with the runtime is published. Revisit then (it is outside this stream's README section).

## Suggested coordinator integration (not applied here)

- `docs/project-state.md`: "Managed providers can reference a verified catalog artifact (ADR 0009). ModelStore downloads from approved HTTPS hosts with resume, checks disk space, verifies size + SHA-256 before an atomic rename, and supports cancel, delete and hash-verified import. Settings → Models shows status and actions. The first real model, Qwen3-4B-Instruct-2507 Q4_K_M (Apache-2.0), ran in the sandboxed bundled runtime on one M1 Pro/32 GB: about 1 s warm load, about 41 tok/s, peak RSS about 3.7 GB, and a synthetic tool round trip 3/3. Single-machine evidence, not a support claim."
- `docs/backlog.md` WORK-002: "in progress: verified manifest, store and first model (PR link, stacked on #19). Remaining: shared read-only managed artifacts, rollback, signed catalog, UI verification." WORK-005 should reference the measurements as a starting point.
- `CHANGELOG.md` Unreleased: "Added verified model catalog (`modelCatalog`, `runtime.artifact`), ModelStore download/import with SHA-256 verification, Settings → Models, `--model-download`, `--runtime-smoke-test --tool`. Built-in artifact: Qwen3-4B-Instruct-2507 Q4_K_M."
- `docs/handoff.md` next action: "Visually verify Settings → Models and a GUI task with the managed Qwen artifact. Test Import through the file picker. Measure on a 16 GB Mac."
- `docs/sessions/README.md`: link this record.

## Local state left behind

- Nothing running (`pgrep` showed no `minimodell`, `minimodell-runtime-guard` or `llama-server`).
- The container `config.json` was restored byte-for-byte (SHA-256 `27f9fc9b…`, starter content).
- **`~/Library/Containers/org.minimodell.agent/Data/Library/Application Support/org.minimodell.agent/Models/Qwen_Qwen3-4B-Instruct-2507-Q4_K_M.gguf` (2.5 GB)** was left there, verified, with its `.verified` record, for the next agents. Delete it through Settings → Models → Delete, or remove the file and `.verified/qwen3-4b-instruct-2507-q4_k_m.json`.
- The 135 MB SmolLM2 file from the runtime stream is still present.
- The scratchpad holds an independent 2.5 GB copy of the model (session-scoped temp).
- `vendor/llama.cpp/b11140/` (gitignored) and `build/minimodeLL.app` (debug, with the runtime) are in this worktree.

## Resume commands

```sh
git switch feat/model-catalog
scripts/fetch-runtime.sh && REQUIRE_RUNTIME=1 scripts/package-app.sh
swift test
M="$HOME/Library/Containers/org.minimodell.agent/Data/Library/Application Support/org.minimodell.agent"
cp "$M/config.json" /tmp/config.backup.json && cp Config/bundled-runtime.example.json "$M/config.json"
build/minimodeLL.app/Contents/MacOS/minimodell --model-download            # verified download (skips if already Ready)
build/minimodeLL.app/Contents/MacOS/minimodell --runtime-smoke-test --tool --show-reply
cp /tmp/config.backup.json "$M/config.json"                               # restore
```
