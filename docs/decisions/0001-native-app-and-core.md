# ADR 0001: Fresh SwiftUI app with a reusable core

Date: 2026-09-23. Status: Accepted.

## Context

The original PRD proposed forking Llama-macOS for its menu bar and runtime management. The owner wants an open-source native macOS product with approved model catalogs, MCP agents, audit and enterprise policy, while being new to Swift. The existing app's arbitrary model installation, configuration overrides and network exposure controls would require careful removal or replacement.

## Decision

Build a fresh SwiftUI app on Swift 6.1/macOS 14, using Swift Package Manager. Separate `LocalAgentCore`, `MinimodeLL`, and `AgentDiagnostics`. Use llama.cpp as the planned local runtime rather than implementing inference. Keep deployment adapters outside the core.

## Alternatives and consequences

A fork could deliver runtime lifecycle sooner but would carry unrelated product choices and upstream maintenance obligations. Electron/Python wrappers could reuse familiar tools but would add another runtime and packaging surface. A fresh Swift implementation makes policy boundaries explicit and permits deterministic core tests; it also means runtime lifecycle and packaging work are genuinely unfinished in this preview.

The external-server preview is an incremental checkpoint, not a change to the self-contained product objective. The next runtime work must address authenticated local communication, sandbox/helper behavior, lifecycle and verified binaries.

## Evidence and revisit conditions

The package builds with the owner's Xcode 16.4 and the app launches with sandbox entitlements. Revisit the package/Xcode project arrangement if signed helpers, resource catalogs or distribution capabilities require a maintained project generator or native project. Document that choice rather than embedding ad hoc manual build steps.
