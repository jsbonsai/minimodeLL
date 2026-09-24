# Architecture decision records

ADRs explain why important choices were made. Add a new numbered record for a consequential change, with status, context, decision, alternatives, consequences and validation needs. Supersede old records by linking both directions; do not erase the historical rationale.

All initial decisions were recorded on 2026-09-23 from the implementation and owner discussion. Accepted means the current design direction, not that every planned consequence is already implemented.

| ADR | Decision | Status |
| --- | --- | --- |
| [0001](0001-native-app-and-core.md) | Fresh SwiftUI app with separate core and diagnostics | Accepted |
| [0002](0002-optional-managed-policy.md) | Standalone configuration with optional complete MDM override | Accepted |
| [0003](0003-explicit-inference-providers.md) | Local llama.cpp direction and explicit LiteLLM selection | Accepted; bundled runtime pending |
| [0004](0004-bounded-task-execution.md) | Fresh bounded tasks, app-owned tool policy and approvals | Accepted |
| [0005](0005-mcp-and-native-oauth.md) | Official Swift MCP SDK and public native OAuth | Accepted; live interoperability pending |
| [0006](0006-audit-and-validation.md) | Content-free audit and evidence-based validation | Accepted |
| [0007](0007-branding-and-distribution.md) | Central branding, stable identity, DMG and optional PKG | Accepted; production distribution pending |
| [0008](0008-bundled-runtime-lifecycle.md) | App-owned, pinned, sandbox-inheriting llama-server helper with authenticated readiness | Accepted; readiness slice implemented, Developer ID path pending |
| [0009](0009-model-artifact-manifest.md) | Verified model artifact manifest, model store, and first approved model (Qwen3-4B-Instruct-2507 Q4_K_M) | Accepted; trimmed WORK-002 slice implemented, shared read-only artifacts and signed catalogs pending |
| [0010](0010-static-site-generation.md) | Static website rendered from repository Markdown; Actions-based Pages deployment | Accepted; first deployment pending |
