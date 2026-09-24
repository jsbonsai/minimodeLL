# Work session records

Session records preserve findings and work history without requiring private chat transcripts. They are append-only historical records; `docs/handoff.md` and `docs/project-state.md` remain the concise current state.

Use a file such as `YYYY-MM-DD-topic.md`, with an additional suffix if needed. Record:

1. User intent and authorized scope relevant to this session.
2. Starting checkpoint and environment assumptions.
3. Actual changes and the reason for them.
4. Decisions, alternatives and ADR links.
5. Commands/checks actually run, their outcomes, and untested areas.
6. Failures found, fixes, and unresolved concerns.
7. Commits/PRs/issues/CI references when available.
8. Exact next step, blockers, local running processes and uncommitted changes.

Do not include credentials, company message content, private endpoints or unnecessary personal information. Reference sanitized fixtures and repo-relative paths. A later session may append a correction with an explanation; do not silently rewrite a historical failure as a success.

## Records

- [2026-09-23: initial preview](2026-09-23-initial-preview.md)
- [2026-09-23: documentation and GitHub bootstrap](2026-09-23-documentation-and-github.md)

- [2026-09-23: supplied brand assets](2026-09-23-brand-assets.md)

- [2026-09-23: website plan and handoff](2026-09-23-website-plan.md)
- [2026-09-23: GitHub organization and Iru rebrand](2026-09-23-chore-github-org-and-iru.md) — labels, milestones, issues #10–#13 and #15/#17/#18, Kandji→Iru doc rename (PR #14).
- [2026-09-23: bundled runtime readiness slice](2026-09-23-runtime.md) — WORK-001 partial: app-owned llama-server, `RuntimeManager`, sandboxed live proof (PR #19).
- [2026-09-23: verified model catalog and first real model](2026-09-23-model-catalog.md) — WORK-002 partial: `ModelCatalog`/`ModelStore`, Qwen3-4B-Instruct-2507 Q4_K_M live in the bundled runtime (PR #20).
- [2026-09-23: branded README and GitHub Pages site](2026-09-23-site-and-readme.md) — `site/`, README/docs branding, Pages workflow (PR #16).
- [2026-09-23/24: coordinator — merges, review fixes, issue triage](2026-09-23-coordinator.md) — integration of the above into `main`, two pre-merge review fixes, GitHub issue/label/milestone triage, live Pages verification.
