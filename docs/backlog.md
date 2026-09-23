# Ordered implementation backlog

Last reviewed: 2026-09-23. These are future work unless explicitly marked otherwise. GitHub issue links are added during repository bootstrap. The handoff identifies the active task; do not interpret every item as authorization to ship a production release immediately.

## WORK-001 — Own a pinned local runtime lifecycle

Priority: first. Status: open. Dependencies: existing provider boundary and packaging.

Decide and document a signed helper/in-process boundary using a small sandboxed proof of concept. Pin llama.cpp revision and verify source/build provenance. Implement app-owned start, health readiness, endpoint authentication, cancellation, idle unload and cleanup. Prevent accidental connection to a different process on a conflicting port. Tie context/concurrency to policy. Add controlled failure tests for startup error, port collision, crash, hung inference and app termination. Do not require Homebrew on employee machines.

Done means the packaged app can run a known synthetic prompt with an approved local artifact, own the server lifecycle, and demonstrate authentication and sandbox/file access behavior. Document evidence and unresolved platform constraints. An external server or mock response does not satisfy this item.

## WORK-002 — Verified model artifacts and approved catalog management

Priority: next. Status: open. Depends on WORK-001's runtime/model boundary.

Extend stubs into a versioned artifact manifest: source, file size/hash, quantization, license, template identity, runtime compatibility and measured memory/context settings. Add verified installation/import, resumable approved-source downloads, atomic promotion, cancellation, disk-space checks, deletion and rollback. Keep display names separate from identity. Support user installations and separately provisioned managed read-only artifacts without world-writable shared directories.

Done means corrupted/unapproved artifacts cannot be selected and a catalog can change through ordinary config/MDM without a source rebuild. Benchmark approval remains distinct from file integrity.

## WORK-003 — Bound transport memory and prove cancellation behavior

Priority: security gate before real-service rollout. Status: open. Can precede WORK-001 if implementation work focuses on transport safety.

Add pre-buffer/pre-decode MCP response limits and explicit redirect/discovery trust rules. Exercise unresponsive streams, oversized replies, cancellation during connect/discovery/tool/auth, late responses and disconnect races. Ensure deadlines cannot hang indefinitely waiting for an uncooperative child task. Record uncertain external action outcomes distinctly and preserve no automatic write retries. Review authentication headers across redirects.

Done means deterministic HTTP/MCP fixture tests demonstrate bounded memory/read behavior and timely local cleanup. Actual service cancellation remains advisory and must be described honestly.

## WORK-004 — Qualify baseline MCP services and OAuth

Priority: before company pilot. Status: blocked on service details/test accounts. Depends on WORK-003 for hardened transport.

Inventory Gmail, Calendar, Atlassian and Slack endpoints, actual transports, native public-client registration, callback/scopes, tool schemas and read/write permissions. Validate sign-in, refresh, reauthentication, revoked scopes, expired tokens and endpoint changes. Implement logout/revocation and user-visible token persistence failures. Expand schema support through a maintained validator or tested additions; do not ignore constraints. Address structured tool results or legacy SSE only when the actual services require them.

Done means each service has a content-safe reproducible validation record and selected read-only tasks pass. Live credentials stay outside Git and issues. Sending/writing through real employee accounts requires applicable task authorization.

## WORK-005 — Exact context budgets and fleet model qualification

Priority: before hardware support claims. Status: open. Depends on WORK-001/002 and representative service fixtures.

Count the full rendered model template with the correct tokenizer, including schemas, history, tool results and reasoning/output reservation. Add pressure-aware admission and cancellation/unload behavior. Build a synthetic task suite and opt-in user-session runner reporting latency, accuracy, evidence support, peak memory, swap and thermal/power context. Exercise the available 16/24/32/64 GB machines. Define acceptance thresholds before ranking models.

Done means support profiles are measured and reproducible, with content-free reports that optional Jamf policies can collect. A RAM threshold or canned fixture response is insufficient.

## WORK-006 — Validate Jamf, maintain best-effort Kandji, and qualify packaging

Priority: before enterprise pilot/public binaries. Status: open. Depends on runtime packaging and access to signing/MDM test environment.

Use the owner/coworker Jamf sandbox for the first focused enrolled-device run (docs/jamf-test-plan.md). Maintain the same artifacts and an explicitly unvalidated Kandji path (docs/kandji.md); do not claim tenant testing without access. Validate forced-policy precedence, malformed policy, policy removal, version migration, sandboxed preferences and changes during a task on enrolled Macs. Test root diagnostics versus user-session behavior. Produce Developer ID signed, notarized/stapled DMG and PKG; validate install/update/rollback/uninstall on clean Macs. Verify nested runtime signatures and resource access. Define update strategy and required OS/CPU support.

Done means recorded clean-machine and enrolled-device evidence exists. A profile that passes XML lint or an ad-hoc signature is not enough.

## WORK-007 — Audit provenance and actionable failure outcomes

Priority: before enterprise audit claims. Status: open.

Version the audit schema; add policy/artifact/runtime provenance, duration, normalized failure classes, actor/session context with privacy review, and uncertain-action outcomes. Preserve no content/token logging. Test file permission/rotation/write failures and concurrent/cancel paths. Document central collection/export as opt-in with destination/retention constraints; no default telemetry upload.

Done means operators can explain which approved policy/model/tool produced an outcome without collecting prompts or service content. Do not call local files immutable.

## WORK-008 — Product polish and accessible configuration

Priority: after a working local runtime flow. Status: open.

Replace the raw JSON-first setup with approachable model/provider/connection flows while retaining import/export and managed-lock visibility. Add accurate connection/model readiness, onboarding, accessible labels, keyboard navigation, responsive result presentation and explicit partial/uncertain results. Validate menu bar/window lifecycle, concurrent window behavior, sleep/wake and VoiceOver. Consider conservative follow-ups without silently accumulating context.

Done means an unfamiliar standalone user can configure an approved local model and complete a small task, while a managed user understands policy and data destination.
