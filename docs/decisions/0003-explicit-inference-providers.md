# ADR 0003: Local inference plus explicitly selected LiteLLM

Date: 2026-09-23. Status: Accepted; bundled runtime pending.

## Context

Reducing paid inference use is the central motivation. The owner also requests LiteLLM support and approved model stubs, potentially distributed through Jamf. Local tool use still connects to remote services, and cloud inference sends model context to a gateway.

## Decision

Use a provider interface implemented through Chat Completions. A stub selects a configured local provider or HTTPS LiteLLM gateway and its exact model alias. Label the destination in the UI. Do not automatically route oversized or failed local requests to cloud inference. Keep model selection separate from display branding.

For now the local adapter connects to an externally started llama-server. The production direction is a pinned signed bundled runtime, not a dependency on Homebrew at employee endpoints. An artifact manifest must eventually pin model checksum, template, quantization, license and runtime compatibility.

## Alternatives and consequences

Automatic fallback is convenient but could spend budget and move workplace content to a cloud provider without the user noticing. An in-process engine would avoid a local HTTP endpoint but introduces a different native integration and lifecycle tradeoff. Revisit helper versus in-process boundaries during the runtime spike with evidence.

OpenAI-compatible does not mean identical across providers. Validate tool arguments, stop reasons and template behavior against actual pinned versions. An 8B quantized model on 32 GB is a hypothesis for qualification, not a selected or certified model. No large-model RAM tier from the original PRD is approved simply by inclusion there.
