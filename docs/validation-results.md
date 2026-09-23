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
