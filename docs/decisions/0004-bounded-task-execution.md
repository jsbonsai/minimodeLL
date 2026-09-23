# ADR 0004: Bounded tasks and application-owned tool safeguards

Date: 2026-09-23. Status: Accepted.

## Context

The owner wants small useful executions and protection against oversized pasted documents on employee Macs. Input length alone does not control context: tool schemas and results can be much larger than the original question. Small models also need a narrow tool set and reliable action boundaries.

## Decision

Each submission begins with a fresh context. One app task runs at a time. Bound input size, context estimate, output allowance, tool count, tool-result size and elapsed time. Allow one tool call per response. Expose only configured tools; check names, IDs, arguments and configured approval rules before calling the service. Do not automatically retry writes. Reject oversized results and unsupported schemas/content instead of silently dropping evidence.

The initial context mechanism is a conservative byte estimate and is explicitly temporary. Exact tokenizer/template accounting and pressure-aware admission are required before model profiles can be qualified. Conversation history, document ingestion and background autonomy are outside the preview.

## Alternatives and consequences

Unbounded chat is familiar but allows history and tool results to grow unpredictably. A disclaimer alone cannot enforce memory or action policy. Automatic summarization can lose critical evidence and requires its own quality and cost analysis. Bounded tasks can reject requests that a larger setup would accept, so errors must explain how to narrow the task.

A system prompt is behavior guidance. MCP annotations are hints. Approval of a generated action must be based on actual tool arguments. Cancellation is advisory once a remote service has accepted an action. Fake-tool tests establish orchestration behavior; slow-network and real service tests remain necessary.
