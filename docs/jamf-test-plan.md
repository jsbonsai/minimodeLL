# Focused Jamf sandbox validation plan

Status: planned; no enrolled-device tests have run. The owner has a Jamf environment and a coworker can provide a narrowly scoped sandbox test. Use that as the first live MDM validation path. Kandji remains best-effort until a separate environment is available.

## Prepare a scoped test

Agree with the sandbox owner on one nonproduction device/user, a dedicated test scope, app/package version, rollback procedure and test window. Record OS, architecture, RAM, signing identity class, package checksum and Git commit. Do not change production enrollment or broad device groups. Keep company credentials and internal identifiers out of public result records.

Use synthetic policy/tool data. The first test validates configuration delivery and app behavior and needs no company OAuth accounts. Use a properly signed test package under the sandbox owner's distribution practices; do not disable system protections to make a development artifact install.

## Test worksheet

| Step | Action | Expected behavior | Evidence to record |
| --- | --- | --- | --- |
| 1 | Install app package into the test scope | Bundle appears in Applications and opens in the user's session | Version, signing check, launch result |
| 2 | Start with no managed profile | App uses personal/starter policy | User-session mode and model list |
| 3 | Deliver generated forced PolicyJSON with distinctive synthetic model title | App reloads managed policy; settings are locked | Profile delivery result and app state |
| 4 | Change local user config to a different model list | Managed list remains authoritative | App state after reload/new request |
| 5 | Update managed model/provider/limits | Next task uses new snapshot; destination changes require review | Exact fields changed and observed behavior |
| 6 | Deliver malformed JSON or out-of-bounds managed limits | Requests blocked; no user/default fallback | Sanitized error and absence of inference request |
| 7 | Restore valid profile | App recovers on reload | Recovery result |
| 8 | Run explicit-file readiness as MDM/root | Signature and policy checks return metadata only | Exit code; distinguish file validity from effective user policy |
| 9 | Remove profile in sandbox | App returns to personal policy on reload | State and local configuration behavior |
| 10 | Update/reinstall app and inspect user settings | Stable identity/storage behavior recorded | Settings persistence and launch result |
| 11 | Remove test app/profile and restore agreed baseline | Only scoped test changes are removed | Rollback completion |

A long-running request test should use a controlled local fixture and record that the active task retains its initial policy snapshot. Removing or changing MDM policy is not an undo mechanism for remote actions already accepted by a service.

## Evidence and promotion

Create a dated result under `docs/sessions/` or a dedicated validation record, with pass/fail per row and links to the tested commit. Update `docs/project-state.md`, `docs/validation-results.md` and WORK-006 with the actual evidence. Mark partial runs as partial. Do not infer Kandji validation from Jamf success.

Subsequent tests can cover local runtime provisioning, approved artifacts, read-only MCP workflows and user-session performance diagnostics after those capabilities exist. The current app still uses an external inference server and the diagnostics CLI is not a benchmark runner.
