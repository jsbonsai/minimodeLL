# ADR 0005: Official Swift MCP SDK and native public-client OAuth

Date: 2026-09-23. Status: Accepted; live interoperability pending.

## Context

The owner already operates HTTPS MCP services from LibreChat and wants to reuse that service ecosystem in a Swift app. Earlier PRD snippets referred to a transport type that does not match the pinned SDK and omitted a complete native OAuth security flow.

## Decision

Pin the official Swift MCP SDK to 0.12.1 and use its Streamable HTTP transport, discovery and OAuth components. The app supplies ASWebAuthenticationSession presentation and Keychain persistence. Register native public OAuth clients with the stable app callback identity. Support an explicit Keychain bearer account for services that use pre-issued tokens. Do not embed a confidential web client's shared secret.

Bind OAuth storage accounts to the configured server ID, endpoint and client ID. Only configured tools are exposed. Legacy HTTP+SSE and provider-specific behavior are separate interoperability work, not assumed compatibility.

## Alternatives and consequences

Hand-writing MCP/OAuth duplicates security-sensitive protocol work. A Python sidecar would add distribution and lifecycle dependencies. The SDK saves protocol work but still requires validation of discovery trust, redirects, cancellation, result buffering, token persistence and actual service behavior. Pinning does not prove security.

The initial argument validator supports an explicit subset of JSON Schema and rejects unsupported keywords. This may block real tools until a maintained validator or carefully tested extension is introduced. Do not weaken validation merely to make an integration appear functional.

## Information needed later

For each baseline service: actual endpoint, supported transport/version, public-client registration support, approved redirect, scopes, actual tool names/schemas and test-account access. Credentials must be supplied through Keychain/browser interaction, never issues or committed documents.
