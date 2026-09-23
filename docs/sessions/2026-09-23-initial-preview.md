# Session: initial developer preview

Date: 2026-09-23. Recorded retrospectively during the immediately following documentation session, using current code, tool results and conversation context.

## Starting point and intent

The directory held `prd.md` and `prd-addendum.md`, with no implementation or Git repository. The owner wanted a Mac-local alternative for small LibreChat/MCP workplace tasks, later named minimodeLL. They authorized broad implementation and wanted open-source quality, audit, safeguards, optional Jamf, LiteLLM, configurable approved models and future fleet validation.

## Decisions and implementation

A fresh native SwiftUI app was chosen over a Llama-macOS fork. A Swift package separates core, app and diagnostics. The official MCP SDK was pinned to 0.12.1 after checking actual source APIs. Core code implements configuration, forced managed-policy precedence, provider adapters, approved tools, public native OAuth wiring, Keychain persistence, limited schema validation, bounded task execution and metadata audit.

The UI includes a workspace, menu bar, raw-JSON configuration settings, credential storage and an argument review sheet. A policy reload checks selected model/provider destination changes before sending a task. Local and cloud destinations are labeled. There is no automatic cloud fallback.

Build tooling creates an ad-hoc signed sandboxed app; DMG/PKG scripts are present for later validation. Profile generation and a Jamf hardware Extension Attribute use the same optional management boundary. Branding was centralized in a bundled JSON resource. MIT, contributor/security documentation, roadmap and CI definition were added. Historical PRDs received explicit superseded-input notices.

## Validation actually performed

- Swift debug compilation with Xcode 16.4 / Swift 6.1.2 on M1 Pro 32 GB, macOS 15.7.7.
- 15 deterministic tests covering policy, schema, context, approved/denied/unknown/repeated actions, size limits, cancellation before execution and audit failures.
- Both configuration examples validated through the CLI.
- Generated mobileconfig passed `plutil -lint`.
- Packaged app passed strict codesign verification with sandbox/network entitlements.
- App window and settings inspected through macOS accessibility and screenshot capture.
- Synthetic UI task returned the explicitly labeled canned response from the local fixture; no LLM or remote account participated.
- Shell syntax checks for packaging/inventory scripts passed.

Small final MCP changes to bind callbacks to configurable identity and reject unsupported result content were rebuilt and packaged after the final recorded 15-test run. They did not receive a live MCP test. The subsequent bootstrap session should establish a hosted CI checkpoint for the complete committed source.

## Failures and fixes

- An SDK constructor did not accept an assumed logger parameter; fixed against pinned source.
- MCP text content enum carried annotations/metadata, requiring the correct associated-value pattern.
- Swift entry point named main.swift conflicted with @main; renamed to MinimodeLLApp.swift.
- A SwiftPM resource bundle at the app root caused strict signing failure; packaged branding moved to Contents/Resources with explicit lookup.
- Opening a UserDefaults suite named after the app's own bundle returned nil and crashed at launch; switched to standard defaults for that process.
- Repackaging read-only dependency license copies failed; install copies now use mode 0644.

## Remaining work and ending state

No runtime/model was bundled, downloaded or benchmarked. No actual MCP, OAuth, LiteLLM, Jamf or production distribution test occurred. These limitations were documented. The fixture server was stopped and the app reopened. Git was initialized on main, but this session made no commits or pushes. GitHub bootstrap was authorized in the next owner message.
