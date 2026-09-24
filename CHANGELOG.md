# Changelog

No production release has been published. Version 0.1.0 identifies the current developer preview.

## Unreleased

### Added

- Supplied Twin L app and menu bar icons, adaptive brand palette, Geist typography and in-app branding; reproducible resource synchronization.

- Native macOS SwiftUI task window, menu bar, settings, credential entry and tool approval review.
- Shared Swift core with local/LiteLLM adapters, official MCP SDK integration and native OAuth/Keychain wiring.
- Versioned approved model/provider/tool policy with optional complete forced MDM override.
- Bounded task execution, explicit schema/tool checks, conservative context estimates and metadata audit.
- Policy/hardware diagnostics, Jamf profile generation and hardware inventory example.
- Sandboxed app packaging, DMG/PKG build scaffolding, dependency notices and centralized branding.
- Deterministic core tests, a labeled local UI fixture, CI definition and validation records.
- Shared MDM readiness checks, focused Jamf sandbox plan and best-effort Kandji deployment documentation.
- MIT licensing, contributor/security guidance, detailed ADRs, configuration reference, code map, backlog, session history and agent handoff protocol.

### Limitations

- Local inference still requires an external llama-server and separately obtained model.
- Live service/OAuth qualification, transport hardening, exact token counting, hardware benchmarks and production signing/notarization remain open work.

### Fixed

- Fake-inference unit fixtures no longer assume a 16 GB CI machine; a dedicated test covers physical-memory admission separately.
