# Security

This is a developer preview, not an enterprise-certified product. Please report vulnerabilities privately to the repository maintainer using GitHub's private vulnerability reporting once the public repository enables it. Until then, do not post credentials or sensitive logs in public issues.

## Implemented boundaries

- Packaged app sandbox and Hardened Runtime; no privileged helper or shell tools.
- HTTPS for remote providers/MCP; literal loopback for local inference; no inference redirects.
- Complete managed policy replacement, endpoint/model validation and explicit tool allowlists.
- Tool argument validation and application-owned confirmation requirements.
- Keychain credentials and native browser PKCE flow through the official MCP SDK.
- Bounded request/context/steps/results and metadata-only audit records.

## Limits and open work

A system prompt is behavior guidance, not authorization. Tool outputs remain untrusted. Approvals must be evaluated from the actual arguments, not the model's explanation. MCP servers must enforce authorization themselves. A local administrator can modify this preview, its policy sources, and local audit files.

Local inference does not make tool use offline. MCP services receive tool arguments; cloud providers receive task context and tool results when explicitly selected. The app never silently changes from local to cloud inference.

MCP response caps currently apply after the SDK has received/decoded the result. This protects model context but does not yet bound transport memory against a malicious server. OAuth discovery/redirect trust, legacy transport interoperability, Keychain persistence failure reporting, and a full JSON Schema implementation need further validation. Do not connect untrusted servers.

The external llama-server process is outside the app sandbox. Shipping a signed managed runtime, authenticating it and enforcing memory budgets are required for the self-contained production design. App Sandbox is not a blanket protection from all same-user or privileged inspection.

Audit records are local diagnostic evidence, not immutable compliance records. Configure central collection and retention separately if required. Cancellation cannot undo a completed external action; writes are never automatically retried by the task runner.
