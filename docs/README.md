# Documentation map

This project keeps implementation context in version control so a human or AI contributor can resume without the original conversation. Read the current checkpoint before changing code.

| Document | Purpose | Update when |
| --- | --- | --- |
| [Handoff](handoff.md) | Immediate resume instructions and active checkpoint | Every work session |
| [Project state](project-state.md) | What exists, what was checked, and what is missing | A capability or validation status changes |
| [Backlog](backlog.md) | Ordered work with acceptance criteria and dependencies | Work is opened, started, blocked, or completed |
| [Architecture](architecture.md) | Component/data flow and implementation boundaries | Boundaries or execution flow change |
| [Decisions](decisions/README.md) | Rationale, alternatives, and consequences | A consequential choice is made or revised |
| [Website plan](website-plan.md) | Proposed GitHub Pages landing/docs and repository branding; not implemented | Website decisions or implementation progress |
| [Branding](branding.md) | Supplied artwork, runtime mapping and status semantics | Visual identity/resources change |
| [Code map](code-map.md) | File-level responsibilities and change entry points | Modules or ownership move |
| [Configuration reference](configuration-reference.md) | Fields, defaults, constraints, and example semantics | Configuration or policy behavior changes |
| [Development runbook](development.md) | Reproducible commands, fixture usage, known build issues | Build/debug workflow changes |
| [Jamf test plan](jamf-test-plan.md) | Scoped live sandbox acceptance worksheet | Scope or evidence changes |
| [Kandji](kandji.md) | Best-effort provider workflow and untested assumptions | Vendor workflow or evidence changes |
| [Deployment](deployment.md) | Standalone and optional Jamf distribution | Packaging/management behavior changes |
| [Validation plan](validation.md) | Test strategy and fleet qualification gates | Support criteria or validation mechanisms change |
| [Validation results](validation-results.md) | Evidence actually obtained and its limits | A relevant check is performed |
| [Roadmap](roadmap.md) | Broad release direction | Milestone scope changes |
| [Session records](sessions/README.md) | Historical work and discoveries | Every material session |
| [Security](../SECURITY.md) | Implemented boundaries and unresolved security work | Threat model or boundaries change |
| [Contributing](../CONTRIBUTING.md) | Contributor workflow | Workflow changes |
| [Changelog](../CHANGELOG.md) | User/contributor-visible changes | Material behavior changes |
| [Agent instructions](../AGENTS.md) | Required reading and documentation protocol | Collaboration practices change |

## Authority and freshness

Source code establishes current behavior. Validation records establish observed behavior in a particular environment. Accepted ADRs establish intended architecture. The backlog and roadmap establish future work; neither is proof of implementation. If those disagree, document and resolve the mismatch.

`prd.md` and `prd-addendum.md` are historical inputs retained for context. Their original API snippets, sandbox assertions, model tiers, world-writable directory example, and OAuth assumptions are not authoritative implementation instructions.

Dates use calendar dates in the project owner's development timezone unless a record explicitly uses UTC. Git history identifies exact changes; document timestamps alone are not a revision system.

## Recording uncertainty

Prefer precise status language:

- **Implemented:** a code path exists.
- **Unit tested:** deterministic tests exercised a specified behavior.
- **Fixture tested:** a controlled synthetic service exercised a protocol/UI path.
- **Live validated:** tested against a named real integration with permitted data.
- **Fleet validated:** tested on recorded devices and management conditions.
- **Planned:** no completed implementation claim.

For example, OAuth is implemented through the SDK and native browser delegate, but company OAuth interoperability is not live validated. The app is sandboxed, while the external inference process is currently outside that sandbox.
