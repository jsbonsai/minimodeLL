# Contributing

Use Swift 6.1+, macOS 14+, and Apple Silicon. Open Package.swift in Xcode or use SwiftPM. Run `swift test` and `scripts/package-app.sh` before proposing changes to policy, orchestration or packaging.

Keep policy/inference/MCP behavior in LocalAgentCore and macOS presentation in MinimodeLL. Keep Jamf scripts outside the core. Add meaningful regression tests for safety boundaries and real bugs. Use synthetic content; never commit service credentials, employee data, model weights or generated build output.

Document whether a feature is implemented, validated with fixtures, validated against a live service, or still planned. A mock integration test is not evidence that a model makes correct decisions.

Before a public release, choose a maintainer contact, enable private vulnerability reporting, verify third-party notices, and publish measured support boundaries. Public publishing is separate from building this local repository.

## Durable project context

Read AGENTS.md and docs/handoff.md before starting. Update documentation in the same commit as behavior changes: current state, relevant ADR/configuration docs, validation evidence, backlog, changelog and the active handoff. Add a session record for substantial work. Record concrete next steps and blockers; do not require a private chat transcript to understand a PR.
