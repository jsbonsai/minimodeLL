# ADR 0006: Content-free audit and explicit validation evidence

Date: 2026-09-23. Status: Accepted.

## Context

The owner prioritizes auditability, enterprise safeguards, and repeatable validation across 16/24/32/64 GB Apple Silicon machines. Logging complete prompts or service output would create another store of sensitive workplace data.

## Decision

Record run IDs, configured model/tool IDs, timestamps and event categories in local JSONL. Emit a smaller metadata event through OSLog. Keep bounded local retention and block progression if audit writing fails. Do not log request/response content, arguments or credentials. Do not claim local logs are tamper-proof or centrally collected.

Use deterministic fixtures for orchestration tests, explicit local HTTP fixtures for UI connectivity, real integration qualification for service behavior, and synthetic benchmark suites for model/hardware claims. Keep a written distinction between these evidence levels. Provide a read-only policy/hardware CLI usable from MDM without signing into user services.

## Alternatives and consequences

Full request tracing eases debugging but risks disclosing company data. OSLog alone does not establish enterprise collection or durable retention. Background MDM benchmarks could disrupt users and misuse root credentials. Future performance validation should be opt-in, in the appropriate user session, with power/thermal context and content-free reports.

The preview lacks provenance hashes, durations, structured failure codes and uncertain-write outcomes. These belong to tracked audit work. Central forwarding must have explicit destination, data and retention semantics rather than being turned on by default.
