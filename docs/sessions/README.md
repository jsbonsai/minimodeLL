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
