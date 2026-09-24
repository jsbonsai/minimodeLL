# Stopping point — owner upgrading to macOS Tahoe 26.7 for Liquid Glass

Date: 2026-09-23 (late evening). Status: **paused on purpose.** The owner is upgrading the development Mac from macOS 15.7.7 / Xcode 16.4 to **macOS Tahoe 26.7** plus the current **Xcode 26.x**, so the app can adopt Apple's Liquid Glass. The next session resumes the same work (the owner plans to continue this Claude Code conversation; if context is lost, this file plus `docs/handoff.md` is enough).

## Where `main` stands

`main` at merge of PR #28 (`8e338ec`) plus this checkpoint's docs. Everything below is merged, pushed, and green in hosted CI unless noted.

| Area | State |
| --- | --- |
| Bundled runtime (WORK-001, #1) | Merged (PR #19). Pinned llama.cpp b11140, sandboxed helper, loopback + per-launch key, readiness, idle unload, guard process. |
| Model catalog (WORK-002, #2) | Merged (PR #20). Qwen3-4B-Instruct-2507 Q4_K_M verified download; ~41 tok/s on the M1 Pro. |
| LAN inference (WORK-016, #21) | Merged (PR #24). `lan` provider kind. **Live test on the owner's M2 Max + LM Studio still pending.** |
| MCP server management (WORK-017, #22) | Merged (PR #27). Settings → MCP Servers CRUD, custom headers, secrets in Keychain. |
| Smart-dash fix | Merged (PR #30). Owner's live bug: `--` in an API key became an em dash in a non-secret header field. The app now disables smart dashes/quotes/text replacement and gives a specific error. |
| Command bar (WORK-009, #10) | Merged (PR #28) with all 13 review fixes (approval arming window, contrast, workspace opener, hotkey status, VoiceOver, LAN chip). 112 tests. |
| Site | Live at https://jsbonsai.github.io/minimodeLL/ (tagline "Local models. MCP tools. Managed by IT."). |

## Owner feedback that defines the next sprint

After using the ⌥Space command bar: *"looks slick, but doesn't feel like they are both the same product… we are also missing the key transparency… I want full Liquid Glass UI implementation."* Tracked as **WORK-020, issue #31 (P1, v0.2)**.

Planned approach (future work, not started):

1. Verify the toolchain first: `sw_vers` (expect 26.7), `xcodebuild -version` (Xcode 26.x), `swift --version` (Swift 6.2+). Run `swift test` and `REQUIRE_RUNTIME=1 scripts/package-app.sh` on the new OS **before** changing UI code, and record any regressions (sandbox, runtime helper signing, Local Network prompt) in `docs/validation-results.md`.
2. One design system for every surface: command bar, menu bar menu, workspace window, Settings (Models, MCP Servers, Credentials, Configuration, Command Bar), approvals. Build on the tokens in `Sources/MinimodeLL/Design/`.
3. Liquid Glass (`glassEffect`, `GlassEffectContainer`, glass button styles, toolbar/sidebar glass) behind `if #available(macOS 26, *)`; keep the deployment target at macOS 14 with the existing vibrancy materials as the fallback. Respect Reduce Transparency / Increase Contrast; check text contrast on glass.
4. Move CI to a macOS 26 runner image with Xcode 26 (or guard glass code with `#if compiler(>=6.2)`), otherwise hosted builds break. Consider keeping a macOS 15 job for the fallback path.
5. Visual verification: on macOS 26 the agent can render previews with `minimodell --render-design-previews <dir>`; real glass needs on-screen capture, which requires Screen Recording permission for the terminal — ask the owner to grant it (System Settings → Privacy & Security → Screen Recording) so screenshots of the real app are possible.
6. Rebuild and relaunch the packaged app for the owner after merging (standing owner request: keep the latest build running on this Mac). Do **not** let background agents `pkill` the owner's app while he is using it.

## Waiting on the owner (unchanged, not blocked by the upgrade)

- **HTTPS MCP server (Google Calendar):** owner has the URL and an `x-api-key`. Add it in Settings → MCP Servers with the header marked **Secret**, Test connection, allow only read-only tools with confirmation on. Never paste the key into chat or Git.
- **M2 Max + LM Studio:** running on the LAN. Needed: its IP, the model name LM Studio shows, and whether an API key is required. Then add a `lan` provider (see `Config/lan-lmstudio.example.json`) and allow the macOS Local Network prompt.
- `gh auth refresh -s project,read:project` (Project board), social preview upload, Jamf sandbox via coworker, Iru sandbox via vendor.

## Local machine state at pause

- Packaged app `build/minimodeLL.app` from `main` @ `8e338ec` was running (menu bar). Build products are ignored by Git and must be rebuilt after the OS upgrade (`scripts/fetch-runtime.sh && REQUIRE_RUNTIME=1 scripts/package-app.sh`).
- The app container config was switched to `Config/bundled-runtime.example.json` (bundled Qwen3-4B). The original starter config is backed up next to it as `config.backup-starter-2026-09-23.json`. Container: `~/Library/Containers/org.minimodell.agent/Data/Library/Application Support/org.minimodell.agent/`.
- Models in the container: Qwen3-4B (2.5 GB, verified) and SmolLM2-135M (smoke test). Keep them.
- No background agents, servers, or workflows running. No uncommitted work besides this checkpoint.

## Resume commands

```sh
cd ~/dev/minimodel
git status --short && git log -5 --oneline && git pull
sw_vers && xcodebuild -version && swift --version
swift test
scripts/fetch-runtime.sh && REQUIRE_RUNTIME=1 scripts/package-app.sh
codesign --verify --strict --deep build/minimodeLL.app && open build/minimodeLL.app
gh issue view 31
```
