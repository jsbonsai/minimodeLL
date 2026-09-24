# 2026-09-23: Raycast-inspired command bar and design system (WORK-009)

Branch: `feat/raycast-design`, based on `main` at `15163e9`. Issue: #10. Spec: [`docs/design/raycast-redesign.md`](../design/raycast-redesign.md). Evidence: `docs/validation-results.md`, section "Command bar and design system". Previews: `docs/design/previews/`.

## Intent and scope

The owner asked for a slick, translucent, animated, keyboard-first launcher-style UI in the spirit of Raycast, as a portfolio piece, before live testing. This stream delivered a written design spec, a design-token layer, a floating command bar panel with a configurable global hotkey, an inline approval card, a ⌘K action panel, a light Settings restyle, an offline preview renderer, and tests. Core policy semantics were not changed.

Parallel-run rules: this stream did **not** edit `docs/handoff.md`, `docs/project-state.md`, `docs/backlog.md`, `CHANGELOG.md` or `docs/sessions/README.md`. Suggested text is at the end. Another stream is adding an "MCP Servers" Settings tab; the `TabView` shape was kept and one tab line was inserted after Models to keep the diff small.

## Findings

- The brand kit's tokens (`tokens.json`, `brand.css`) already define a complete light/dark palette; the dark status colors needed lightening to keep ≥ 4.5:1 on ink, which the spec records as derived values.
- `RegisterEventHotKey` (Carbon) is the right global-shortcut mechanism for a sandboxed app: it needs no Accessibility or Input Monitoring permission and delivers only the registered combination. A global `NSEvent` monitor or `CGEventTap` would have required permission and would observe all keystrokes.
- `ImageRenderer` cannot draw `NSVisualEffectView`, `TextField` or `ScrollView` content. The renderer therefore uses an opaque material fallback, a static text stand-in for the field and stacks instead of scroll views, selected through environment keys so the live view is unchanged.
- SwiftPM can test the executable target with `@testable import MinimodeLL`; the tests construct a real `AppState`, which installs the starter configuration in the test process's Application Support if absent (same as `swift run`).
- Placing `MenuBarExtra` before the `WindowGroup` stops SwiftUI from opening the workspace window at launch, so the bar becomes the first surface.
- The sandboxed `.app` cannot write previews to the scratchpad; the renderer must run from the SwiftPM build.
- `screencapture -l <window>` fails with "could not create image from window" without Screen Recording permission and does not prompt from a shell; `CGWindowListCopyWindowInfo` still reports window geometry, which was enough to verify the panel's placement and size.

## Changes

New files:

- `Sources/MinimodeLL/Design/Tokens.swift`, `Materials.swift`, `Motion.swift`, `Hotkey.swift`, `DesignPreviews.swift`.
- `Sources/MinimodeLL/CommandBar/CommandBarState.swift`, `CommandBarView.swift`, `CommandBarPanel.swift`, `CommandBarController.swift`, `CommandBarSettings.swift`.
- `Tests/MinimodeLLTests/HotkeyTests.swift`, `CommandBarStateTests.swift`, `CommandBarKeyTests.swift`.
- `docs/design/raycast-redesign.md`, `docs/design/previews/*.png` (12 images).

Edited:

- `Package.swift`: new `MinimodeLLTests` target depending on `MinimodeLL`.
- `Sources/MinimodeLL/MinimodeLLApp.swift`: creates `CommandBarController` in `init` and registers the hotkey; `MenuBarExtra` first; `--render-design-previews <dir>` and `--open-command-bar`; `designRoot()` on the workspace and Settings scenes; menu item "Command bar ⌥Space" and "Open workspace window"; Settings gains a "Command Bar" tab; `WorkspaceOpener` hands the `openWindow` action to the controller.
- `docs/code-map.md`, `docs/development.md`, `docs/branding.md`, `docs/configuration-reference.md`, `docs/validation-results.md`.

Not changed: `LocalAgentCore` (no file touched), `AppState.swift` (only an extension in the CommandBar folder adds `commandBarInputs`).

## Design decisions

- **The bar is a view over `AppState`, never a second state machine.** `CommandBarModel.resolve` is a pure function of plain inputs; approval goes through `AppState.decide` into the existing `TaskRunner` continuation; submit goes through `AppState.submit`, which re-resolves policy. There is no way for the bar to run a tool the core did not propose or approve one without the user's key press. Plain ↩ never approves; ⌘↩ approves, ⌘⌫ denies.
- **Hotkey is a per-user preference, not policy** (`UserDefaults` `commandBarHotkey`). It grants nothing, so it does not belong in `PolicyJSON`; an invalid value falls back to ⌥Space; at least one modifier is required so no bare key can be captured system-wide.
- **Window follows content.** The panel is transparent and its height tracks the SwiftUI card (preference + `NSHostingView.sizingOptions = .preferredContentSize`) with the top edge anchored, so expanding sections never move the input. The entrance is a SwiftUI scale-in under a window fade; an AppKit frame animation was tried first and removed because it fought the height follower.
- **Reduce Motion / Reduce Transparency** are read in one place each (`Motion.swift`, `DesignRoot`) and switch to crossfades and opaque surfaces rather than a separate "accessible" layout.
- **Suggestions insert text only.** The idle list is three starter prefixes; ↩ fills the field and never submits.
- **Esc hides, it does not cancel or deny.** A running task keeps running and a pending approval stays pending; an approval arriving while hidden brings the bar back.
- No ADR was added: the change is presentation-only and the spec document records the choices. If the owner wants the workspace window removed later, that would deserve an ADR.

## Validation actually run

- `swift test`: 73 passed.
- `minimodell --render-design-previews`: rendered 20 PNGs; iterated three times on the images (static text field stand-in, footer status colors, chip separator, ⌘K panel fit, flat background for repository-sized files).
- `scripts/package-app.sh` + `codesign --verify --strict`: passed.
- Packaged launch with `--open-command-bar`: panel on screen at 680 × 250, level 3, top-anchored; no workspace window at launch; container config unchanged (SHA-1 `44a6ff0b…`); models untouched; app quit cleanly.

## Not tested

- The hotkey firing, typing, ⌘K, approval keys and phase transitions in the live panel (unit-tested only).
- Real vibrancy and light/dark of the live panel; Reduce Motion / Transparency toggles; multi-display placement; hide on focus loss; the Settings → Command Bar tab; the restyled Settings and workspace windows; a real task through the bar.
- CI on macOS 15 (checked after push; see PR).

## Failures found and fixed

- `CardHeightKey.reduce` took the last sibling's value, so the hidden ⌘K branch's default (0) replaced the card height and the panel stayed 62 pt tall. Fixed with `max`.
- The show animation captured the 62 pt frame and animated the window back to it after the height follower had grown it. Replaced by a SwiftUI scale-in plus window alpha fade.
- ImageRenderer drew the `TextField` as a yellow placeholder; replaced with a static stand-in under `staticLayout`.
- The first `open -n` right after `pkill` returned nonzero while the previous instance was still exiting; relaunching after a pause worked.

## Remaining work

- Live keyboard verification with a human (or with Accessibility permission granted to an automation tool): hotkey, ⌘K, approval keys, focus loss.
- A hotkey recorder control instead of the text field; Increase Contrast pass; VoiceOver walkthrough.
- Decide whether the workspace window stays (it still works and is reachable via ⌘O / the menu) or becomes a "details" view; ADR if removed.
- Optional: light restyle of `ModelsSettings` rows with the tokens (only the scene-level font/tint/palette was applied to avoid conflicts with the MCP Servers tab stream).
- README/site could use `docs/design/previews/command-bar-idle-dark.png` and `command-bar-approval-light.png`.

## Suggested coordinator integration (not applied here)

- `docs/project-state.md`: "A floating command bar (⌥Space by default, Settings → Command Bar) is the primary surface: request, model/destination chip, streaming-style status, inline approval (⌘↩ / ⌘⌫), result and error cards, ⌘K actions. It is a view over `AppState`; policy, approval and limits are unchanged in `LocalAgentCore`. Reduce Motion and Reduce Transparency are honoured. Verified: unit tests and a packaged launch with window geometry; live keyboard interaction not yet verified."
- `docs/backlog.md` WORK-009: "implemented on feat/raycast-design (PR link); remaining: live keyboard verification, hotkey recorder, Increase Contrast, VoiceOver pass, workspace window decision."
- `CHANGELOG.md` Unreleased: "Added a Raycast-style floating command bar with a configurable global hotkey (`RegisterEventHotKey`, sandbox-safe), inline tool approval, ⌘K action panel, design tokens from the brand kit, `--render-design-previews`, `--open-command-bar`, Settings → Command Bar, and a `MinimodeLLTests` target. The workspace window no longer opens at launch; use ⌘O or the menu."
- `docs/handoff.md` next action: "Verify the command bar by hand: press ⌥Space, type, ↩ against `scripts/mock-inference.py`, then a managed-runtime task with a tool approval. Record in validation-results."
- `docs/sessions/README.md`: link this record.

## Local state left behind

- Nothing running (`pgrep -x minimodell` empty after quit).
- Container `config.json` unchanged; both model files still in the container.
- `build/minimodeLL.app` (debug, external-server mode) in this worktree; previews also in the session scratchpad.

## Resume commands

```sh
git switch feat/raycast-design
swift test --filter MinimodeLLTests
.build/debug/minimodell --render-design-previews /tmp/previews      # run from the SwiftPM build, not the .app
scripts/package-app.sh && codesign --verify --strict build/minimodeLL.app
open -n build/minimodeLL.app --args --open-command-bar               # then press ⌥Space, ⌘K, esc by hand
pkill -x minimodell
```
