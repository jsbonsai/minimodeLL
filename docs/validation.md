# Validation plan

## Automated now

Run `swift test`. Deterministic fake model/tool tests cover rejected endpoints, credential-bearing URLs, broken model references, excessive limits, context accounting, schema constraints, approval denial, unknown tools, successful approved actions, oversized tool results, oversized input, and audit payload shape.

Run `swift run minimodell-diagnostics --config Config/local.example.json` to validate a policy and report hardware eligibility. CI runs on macOS and also packages the sandboxed app.

## Hardware matrix

| Device | RAM | Initial purpose |
| --- | --- | --- |
| M1 Pro | 16 GB | Minimum supported model configuration and pressure behavior |
| MacBook Air | 24 GB | Sustained thermal behavior and battery use |
| M1 Pro | 32 GB | Primary development and baseline tool accuracy |
| M2 Max | 64 GB | Compare larger approved models and context settings |

No performance numbers have been measured yet. Do not market RAM tiers as quality guarantees.

## Model qualification

Pin the runtime revision, model SHA-256, quantization, chat template, context, and decoding settings. Use synthetic fixtures with expected tool names and arguments. Include: today's email summary, timezone-sensitive calendar queries, Jira lookup, Slack search, missing permission, zero results, ambiguous recipient, adversarial instructions in a tool result, malformed tool arguments, oversized output, expired OAuth, and interrupted writes.

Record correct-tool rate, argument accuracy, final-answer support in the returned evidence, rejected action rate, completion latency, peak resident memory, swap growth, pressure events, and battery/thermal conditions. Set pass criteria before comparing models. Do not use real employee messages in public fixtures.

## Production gates

- Actual Gmail, Calendar, Atlassian and Slack OAuth and transport interoperability.
- Signed runtime bundle and controlled model installation; download hash checks and rollback.
- Exact tokenizer/template accounting and pressure-aware local admission.
- Cancellation and timeout against slow/nonresponsive HTTP and MCP servers.
- MCP transport response byte limits before buffering; validate redirects and discovery trust boundaries.
- Managed policy delivery, removal and invalid-policy behavior on real Jamf enrolled devices, following docs/jamf-test-plan.md. Repeat independently in Iru (formerly Kandji) if a tenant becomes available; keep Iru explicitly unvalidated until then.
- Sandbox, Keychain persistence and OAuth callback behavior under stable Developer ID signing.
- Accessibility, menu bar lifecycle, sleep/wake, logout, crash recovery and clean uninstall.
- Notarized DMG and PKG installation on clean machines.
