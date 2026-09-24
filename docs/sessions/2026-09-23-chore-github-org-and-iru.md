# Session: GitHub organization and Iru rebrand — 2026-09-23

Agent: Claude Haiku 4.5 (1M context)
Stream: chore/github-org-and-iru
Timeframe: 2026-09-23 to 2026-09-24

## Summary

Organized GitHub repository structure by creating a comprehensive label set, three milestones (v0.2, v0.3, v0.4), and four new tracking issues (#10-#13). Completed Kandji→Iru rebrand across six documentation files. All metadata changes committed; PR pending.

## Validation Actually Run

None. This is organizational/documentation work with no code execution, tests, or runtime validation.

## Changes Made

### GitHub Labels (Created)

All labels created successfully via `gh label create`:
- **Area labels** (9): runtime, models, mcp, policy, mdm, ui, site, packaging, audit
- **Type labels** (4): feature, security, docs, validation
- **Priority labels** (3): p1, p2, p3
- **Blocked label** (1): owner-input

Verified with `gh label list` — all 17 new labels present with correct colors and descriptions.

### GitHub Milestones (Created via API)

Three milestones created via `gh api repos/jsbonsai/minimodeLL/milestones`:
1. **v0.2 Working local demo** (ID 1) — Bundled runtime, first model, site, one live MCP server
2. **v0.3 Enterprise pilot** (ID 2) — Jamf sandbox validation, signing/notarization, audit provenance, OAuth qualification
3. **v0.4 Product polish** (ID 3) — Raycast-style UI with transparency, animations, keyboard-first design, accessibility refinements

### GitHub Issues (Created)

Four new issues created via `gh issue create`:

**#10 — Raycast-inspired UI/UX redesign**
- Labels: area:ui, type:feature, priority:p3
- Milestone: v0.4 Product polish
- Context: Owner wants slick, modern launcher-style UI like Raycast with translucent vibrancy materials, global hotkey invocation, smooth animations, keyboard-first, accessibility (Reduce Motion/Transparency)
- Relates to: #8

**#11 — Connect first live HTTPS MCP server**
- Labels: area:mcp, type:feature, priority:p1, blocked:owner-input
- Milestone: v0.2 Working local demo
- Context: Owner will provide HTTPS MCP server endpoint; app supports Streamable HTTP only, not legacy HTTP+SSE
- Requires: endpoint, auth mode (OAuth client with redirect org.minimodell.agent://oauth-callback, or bearer token in Keychain), exact tool names
- Relates to: #4, #7

**#12 — Iru (formerly Kandji) sandbox validation**
- Labels: area:mdm, type:validation, priority:p1, blocked:owner-input
- Milestone: v0.3 Enterprise pilot
- Context: Owner plans to request Iru (formerly Kandji, rebranded 2026-09-24) sandbox access via vendor contact; critical for enterprise pilot
- Relates to: #6, SECURITY.md (MDM deployment section)

**#13 — GitHub Pages site and branded README**
- Labels: area:site, type:docs, priority:p1
- Milestone: v0.2 Working local demo
- Context: Separate agent opening PR for site and README; tracking issue documents work completion
- Status: In progress (PR expected soon)
- Relates to: #1

### Documentation: Kandji→Iru Rebrand

Updated 6 files to rename Kandji to Iru (formerly Kandji), preserving historical context and documenting the rebrand source:

1. **docs/kandji.md** — Updated title, support descriptions, vendor documentation links, and added Iru rebrand context
2. **docs/deployment.md** — Deployment paths, table row, and associated descriptions
3. **docs/jamf-test-plan.md** — Validation path descriptions
4. **docs/validation.md** — Production gates MDM validation step
5. **AGENTS.md** — Product intent section
6. **docs/decisions/0002-optional-managed-policy.md** — ADR clarification section with rebrand deadline note

Commit: `229be8f` with full message documenting each file updated.

## What Was NOT Tested

- GitHub Project board creation (attempted `gh project create --owner jsbonsai --title "minimodeLL roadmap"` but auth token lacks required `project` scope)
- Issue label/milestone assignment after creation (labels and milestones created independently via API; no cross-linking in this session)
- CI pipeline behavior

## Decisions

1. **Project board blocked** — Token lacks `project` and `read:project` scopes. Recorded exact command owner must run in needs_owner field below.
2. **File naming preserved** — docs/kandji.md file name unchanged to avoid breaking historical links; content migrated to Iru (formerly Kandji) terminology.
3. **Rebrand scope** — Limited to technical documentation and deployment guides; excluded README.md and site docs (those handled by separate agent per coordination rules).

## Blocked / Needs Owner Input

1. **GitHub Project creation requires auth scope**
   - Token needs `project` and `read:project` scopes
   - Owner can run: `gh auth refresh -s project,read:project`
   - Once refreshed, create the project with:
     ```
     gh project create --owner jsbonsai --title "minimodeLL roadmap"
     ```
   - Then add issues to board: `gh project item-add <project-id> --owner jsbonsai --id <issue-number>`

2. **Vendor rebrand verification** — Kandji→Iru rebrand confirmed via official migration notice on support pages (December 1, 2026 deadline). Support domain migrated from support.kandji.io to support.iru.io. Recommend owner verify current vendor documentation before first Iru sandbox deployment.

## Next Steps (Not In This Session)

1. Push this branch and open PR (main branch protection blocks direct merge)
2. Verify CI passes; any failures are non-blocking for organizational work
3. Coordinate issue assignment to milestones after other PRs merge
4. Owner provides HTTPS MCP server details for #11 resolution
5. Owner initiates vendor sandbox requests for #12 (Iru) and #11 (Jamf if not already done)

## Remaining Work

- [ ] Project board creation (blocked on owner auth refresh)
- [ ] Apply labels to issues #1-#8 (retroactively, if desired)
- [ ] Assign existing issues to milestones (coordinate with other agents)
- [ ] Verify CI passes on PR

## Resume Commands

```bash
cd /Users/apple/dev/minimodel/.claude/worktrees/wf_f7172c11-682-3
git log --oneline chore/github-org-and-iru -5
gh pr create --title "Organize GitHub roadmap and rename Kandji to Iru" --body-file /path/to/pr-body.txt
```

## Artifacts

- Issue #10: https://github.com/jsbonsai/minimodeLL/issues/10
- Issue #11: https://github.com/jsbonsai/minimodeLL/issues/11
- Issue #12: https://github.com/jsbonsai/minimodeLL/issues/12
- Issue #13: https://github.com/jsbonsai/minimodeLL/issues/13
- Commit: 229be8f (chore/github-org-and-iru)
