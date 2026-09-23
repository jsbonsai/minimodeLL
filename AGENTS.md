# Agent instructions for minimodeLL

## Start here after every handoff

1. Read `docs/handoff.md` for the active checkpoint, next work, constraints, and blockers.
2. Read `docs/project-state.md` to distinguish implementation from validation and plans.
3. Read `docs/decisions/README.md` and the decisions relevant to your change.
4. Read `docs/backlog.md`, then the linked GitHub issue for your selected work.
5. Inspect `git status --short`, `git log -5 --oneline`, and the working tree before editing. Never discard another contributor's work.

The repository is the durable source of project context. A chat transcript is not required to resume work. If these documents contradict code or fresh evidence, investigate and update the affected documents with the reason; do not silently choose the more optimistic interpretation.

## Product intent and boundaries

- Build a shareable, open-source, native Apple Silicon macOS assistant named **minimodeLL**.
- Prioritize focused workplace tasks, approved local models, and existing HTTPS MCP services.
- Support explicit LiteLLM gateway selection. Never introduce automatic cloud fallback.
- Keep the app useful without MDM. Support Jamf and Kandji through the same optional macOS policy/deployment boundary. Jamf is the first live validation target; Kandji is best-effort and unvalidated without a tenant.
- Preserve centralized branding and stable deployed identity. Do not scatter the product name through code.
- Current delivery is a developer preview, not a self-contained or production-qualified release.
- Do not revive historical PRD code or requirements without reading the superseding decisions.

## Engineering rules

- Keep orchestration, policy, provider interfaces, credentials, and audit behavior in `LocalAgentCore`.
- Keep UI and browser-session presentation in `MinimodeLL`; keep Jamf integration in scripts/docs.
- Enforce policy in code. A system prompt or MCP annotation is not an authorization boundary.
- Invalid forced managed policy must fail closed. User settings must not extend managed allowlists.
- Do not log prompts, responses, tool results/arguments, OAuth tokens, or raw remote error bodies.
- Use Keychain for credentials. Never add secrets to examples, profiles, issues, logs, or commits.
- Use synthetic fixtures for public tests and benchmark data.
- Model files and inference binaries are not currently shipped. Do not imply they are installed.
- Public model support claims require recorded model/runtime/template/hardware measurements.
- Preserve explicit approval for configured tool actions and no automatic retry of writes.
- Keep changes scoped to the active issue. Do not add unrelated frameworks or rewrite the app without documenting the decision.

## Documentation is part of the implementation

The owner explicitly requests verbose, durable documentation so another agent can continue after rate limits or context loss. Update documents in the same commit as material behavior changes:

- `docs/project-state.md`: actual capabilities and limitations.
- `docs/handoff.md`: current checkpoint, exact next action, blockers, commands, and environment assumptions.
- `docs/backlog.md`: priority, status, dependencies, and issue links.
- `docs/configuration-reference.md`: configuration additions, defaults, constraints, and migrations.
- `docs/decisions/`: a numbered ADR for a consequential architecture/security/product choice.
- `docs/validation-results.md`: new evidence, environment, scope, failures, and what was not tested.
- `docs/sessions/`: append a dated work record with findings, changes, decisions, validation, and remaining work.
- `CHANGELOG.md`: meaningful user/contributor-visible changes, under Unreleased until actually released.

Do not claim a check passed unless it ran successfully. Distinguish code review, unit tests, protocol fixtures, live integration, sandbox launch, and fleet deployment. Record failures and fixes where they explain a non-obvious choice. Plans and issue acceptance criteria must be labeled as future work.

## Validation

Run checks appropriate to the change. Core execution/security changes generally need `swift test`. Packaging changes need `scripts/package-app.sh` and strict signature verification. UI/lifecycle changes need a packaged app launch; SwiftPM execution alone does not exercise App Sandbox. Configuration changes need both example files validated by the diagnostics tool. Do not launch real authenticated tools or expensive benchmarks simply to test documentation.

Required new evidence belongs in `docs/validation-results.md` or an explicitly linked run record. Once relevant checks pass, avoid repeating unrelated checks.

## GitHub workflow and authorization

The owner authorized creating the repository and ongoing commits and pushes using `gh`. Use ordinary incremental commits and descriptive branches for subsequent feature work. Link issues in PR descriptions; include behavior, validation, and remaining limitations. Keep changes and documentation reviewable. Do not force-push shared history or publish releases/signing artifacts without an applicable request.

The initial repository is public and has an MIT license. Review staged files for credentials, personal data, internal service URLs, large model files, logs, and build products before every push. Store test credentials locally in Keychain. Do not infer authorization to send messages to external services from repository access.

No agent delegation is required. Work locally unless the owner explicitly asks for parallel agents or another applicable instruction authorizes it.

## Before ending work or handing off

- State what changed and why, what was tested, and what remains unverified.
- Update the handoff and project state before committing; cite the preceding checkpoint if the new commit hash is not known yet.
- Record any uncommitted changes, running servers, generated artifacts, and exact resume commands.
- Push authorized work, inspect CI, and record a failed or pending run accurately. Do not call a feature complete merely because code compiles.
