# Roadmap

## 0.1 — developer foundation (current)

Native app, typed configuration, optional managed policy, local/LiteLLM provider interface, MCP/OAuth integration, Keychain storage, bounded task loop, explicit approvals, metadata audit, deterministic tests, diagnostics, and packaging scaffolding.

## 0.2 — self-contained local runtime

Bundle a pinned signed llama.cpp helper; authenticate its loopback API, control launch and idle unload, reject unexpected processes, and react to memory pressure. Add approved model manifests with hashes, licenses, template identity, download resume, verified installation and removal. Separate bundled runtime updates from multi-gigabyte model distribution.

## 0.3 — service interoperability and qualification

Connect the real four baseline MCP services, expand schema compatibility deliberately, tighten response streaming limits and auth trust controls, implement exact token accounting, and run synthetic task benchmarks across the 16/24/32/64 GB fleet. Add optional MDM-triggered, user-session validation with content-free reports.

## 1.0 — public production release

Accessibility and lifecycle polish, update/rollback strategy, centrally collected audit guidance, threat-model review, published measured model profiles, license notices, and Developer ID signed/notarized DMG and PKG releases. No production or compliance claims until these gates pass.
