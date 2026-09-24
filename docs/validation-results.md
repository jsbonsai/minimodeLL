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
