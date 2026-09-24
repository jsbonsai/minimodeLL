# Command bar design spec (WORK-009, issue #10)

Status: implemented on `feat/raycast-design` as a developer preview. Rendered previews live in
[`previews/`](previews/) (offline `ImageRenderer` output; see "Verification"). Code: `Sources/MinimodeLL/Design/`
and `Sources/MinimodeLL/CommandBar/`.

The command bar is the primary way to use minimodeLL: a floating, translucent, keyboard-first panel summoned
with a global shortcut, in the spirit of macOS launchers such as Raycast and Spotlight. The workspace window and
the menu bar item remain. Nothing in the bar changes what the core allows; every action routes through
`AppState` into `LocalAgentCore`, which enforces policy, approval and limits exactly as before.

## Principles

1. **One request, one card.** The bar shows a single task from request to result. There is no history list and
   no conversation; each task starts with a fresh context, and the footer says so.
2. **Keyboard first, mouse welcome.** Every action has a key. Hints are always visible in the footer; the ⌘K
   panel lists everything else. Clicking any row or button does the same thing as its key.
3. **Honest state.** The bar only renders facts it gets from `AppState` (`CommandBarModel.resolve`). It never
   guesses that a model is running, never retries, and never approves on the user's behalf. When policy blocks
   requests the bar says so and disables input; it does not fall back.
4. **Content stays in the card.** Status lines, audit and logs are content-free (`statusLineIsContentFree` test).
   Prompts, results and tool arguments appear only inside the card, selectable, and are never persisted by the UI.
5. **Calm materials, short motion.** Vibrancy and a hairline, a 2 % scale-in, sections that rise 6 pt. Nothing
   bounces. Reduce Motion and Reduce Transparency are respected without a separate mode.
6. **Brand, not decoration.** Ink, paper, graphite, mist and Signal from the brand kit; Geist everywhere; the
   Twin L mark with its status dot is the only illustration.

## Layout

```
┌─────────────────────────────────────────────────────────────────┐
│ [mark]  What can we get done?                [▭ Qwen3 4B · On this Mac] │  header, 62 pt
├─────────────────────────────────────────────────────────────────┤
│  body section for the current phase (see States)                 │  natural height
├─────────────────────────────────────────────────────────────────┤
│ ● status line                             Run ↩   Actions ⌘K     │  footer, 38 pt
└─────────────────────────────────────────────────────────────────┘
```

- Width 680 pt, corner radius 18 pt (continuous), 18 pt horizontal inset, 1 pt hairline border
  (white 10 % dark / black 8 % light), window shadow from AppKit.
- The panel is centred horizontally on the screen under the pointer, its top edge at 22 % of the visible height.
  The window is transparent and resizes to the card's natural height with its top edge anchored, so a section
  expanding never moves the input.
- The ⌘K action panel (300 pt wide, radius 16, `.popover` material) floats above the footer at the trailing
  edge. The card opens far enough for the panel to fit inside the window.

### Command bar anatomy

| Element | Source of truth | Notes |
| --- | --- | --- |
| Mark | `CommandBarModel.markState` | Ring dot idle, solid dot while the core works or waits for approval, no dot when locked |
| Input | `AppState.input` | `TextField(axis: .vertical)`, Geist 19, 1–4 lines, ↩ runs, ⌥↩ inserts a newline |
| Destination chip | `AppState.provider`, `model` | "Qwen3 4B · On this Mac", "Gateway model · Cloud · host", lock glyph when managed. Local providers are loopback-only by policy, so there is no LAN variant |
| Status line | `CommandBarModel.statusLine` | Content-free; mirrors `RuntimeState` for the bundled runtime |
| Key hints | phase | Always shows the primary key and ⌘K |

## States

| Phase | Trigger (`CommandBarModel.resolve`) | Body | Footer |
| --- | --- | --- | --- |
| `locked` | no configuration snapshot (invalid forced policy fails closed) | lock card "Managed policy locked" / "Configuration unavailable", input disabled | red dot "Requests are blocked" · Settings ⌘, |
| `idle` | empty input, no result/error | "Start with" suggestions (↑↓ ↩ insert text only; nothing runs) | runtime state or "Fresh context every task · N tool servers" · Insert ↩ Navigate ↑↓ |
| `typing` | non-blank input | none (card collapses to header + footer) | byte budget when above 75 %, red when over · Run ↩ |
| `modelStarting` | busy and managed runtime `.starting` | pulse dot + "Starting local model…" + indeterminate bar | "Fresh context · stops with ⌘." · Hide esc |
| `running` | busy | pulse dot + "Working on this Mac…" / "…through your gateway…" | same |
| `approval` | `AppState.proposal` set (core is awaiting the decision) | approval card: server → tool, arguments in mono, Deny ⌘⌫ / Approve once ⌘↩ | amber dot "Nothing runs until you decide" |
| `result` | result non-empty | selectable result, max 320 pt then scrolls | green dot "Done · fresh context next time" · Copy ⌘C New ⌘N |
| `error` | error set | red icon card with the user-safe message | red dot "Could not complete · nothing was retried" · Dismiss ⌘N |

Precedence is fixed in code and tested: locked › approval › running/modelStarting › error › result › typing › idle.

Approval details: the card is presentation only. Both buttons call `AppState.decide`, which resolves the same
`TaskRunner` approval continuation the workspace sheet uses. Esc hides the panel but leaves the proposal
pending; an approval that arrives while the bar is hidden brings it back (`watchApprovals`). Plain ↩ never approves.

## Motion

| Token | Value | Used for |
| --- | --- | --- |
| `Motion.quick` | 120 ms ease-out | selection highlight, button press |
| `Motion.standard` | 200 ms ease-in-out | chip and status changes |
| `Motion.expand` | spring, response 0.32, damping 0.86 (no overshoot) | phase changes, card height, ⌘K panel |
| `Motion.panelIn` | spring, response 0.26, damping 0.82 | entrance: card scale 0.98 → 1 (anchor top) while the window fades in over 220 ms |
| panel out | 120 ms fade | Esc / focus loss |
| pulse dot | 900 ms ease-in-out, autoreverse | starting/running |
| progress sweep | 1.1 s ease-in-out, autoreverse | running |

Section transitions: rise 6 pt + fade in, drop 4 pt + fade out.

**Reduce Motion** (`accessibilityReduceMotion`, checked in one place — `Motion.swift` and the controller):
all movement and scale collapse to a 120 ms opacity crossfade, the pulse dot is static, the progress bar becomes
a static half-opacity fill, and the ⌘K panel fades instead of scaling.

## Materials

- Card: `NSVisualEffectView` `.hudWindow`, `.behindWindow`, `.active`, with a rounded `maskImage` so the blur
  stays inside the corners. Hairline border on top so the card reads against any wallpaper.
- ⌘K panel: `.popover` material, radius 16, its own drop shadow.
- Inset surfaces (chips, key caps, argument block): flat `inset` token with a 1 pt `border` stroke, no blur, so
  text on them always meets contrast.
- **Reduce Transparency** (`accessibilityReduceTransparency`) and the offline renderer set `opaqueMaterials` in
  the environment; `Material` then fills the same shape with the palette's `surface` color. Everything else is
  unchanged.

## Typography

Geist (SIL OFL), registered per process by `BrandAssets.registerFonts()`; the system font is the automatic
fallback when a face is missing (unit tests).

| Role | Face | Size |
| --- | --- | --- |
| input | Geist Regular | 19 |
| title (cards) | Geist SemiBold | 15 |
| body / result | Geist Regular | 14, line spacing 3 |
| label / rows | Geist Regular / SemiBold | 13 |
| caption / footer | Geist Regular / SemiBold | 11.5 |
| key cap | Geist SemiBold | 10.5 |
| arguments / config | Geist Mono Regular | 12.5 |

## Color tokens

`DesignPalette` (`Tokens.swift`) maps the brand kit one-to-one; values are plain `Color`s chosen per scheme so
the offline renderer is deterministic.

| Token | Light | Dark | Brand source |
| --- | --- | --- | --- |
| background | `#F2F3EF` paper | `#16181D` ink | `--mm-bg` |
| surface | `#FFFFFF` | `#22252C` inkRaised | `--mm-surface` |
| inset | `#F2F3EF` | `#2B2E36` | derived (surface + 6 % text) |
| text | `#16181D` ink | `#F2F3EF` paper | `--mm-text` |
| muted | `#5B5F68` graphite | `#A3A7AF` | `--mm-text-muted` |
| border | `#E2E4DF` mist | `#33363E` | `--mm-border` |
| accent | `#3A5BD9` signal | `#7D96FF` signalDark | `--mm-accent` |
| accentWash | accent 12 % | accent 16 % | derived (selection rows) |
| running / warning / blocked | `#1F8A5B` / `#B7791F` / `#C23B3B` | `#3DBD85` / `#D9A441` / `#E0605F` | `status.*`; dark values lightened for ≥ 4.5:1 on ink |

Signal is used only for the dot, the selected/prominent control and the tool name, never as a large fill
(brand rule). Spacing follows `space.*` (4/8/12/16/24/32); radii `sm` 6, `md` 10, `lg` 16, `panel` 18.

## Keyboard map

| Keys | Where | Effect |
| --- | --- | --- |
| **⌥Space** (default, configurable) | anywhere | show / hide the bar. Registered with Carbon `RegisterEventHotKey`, which works in the App Sandbox without Accessibility or Input Monitoring permission and only ever delivers the registered combination. Stored in `UserDefaults` (`commandBarHotkey`), a per-user preference, not policy |
| ↩ | idle | insert the selected suggestion |
| ↩ / ⌘↩ | typing | run (`AppState.submit`, which re-resolves policy) |
| ⌥↩ | typing | newline |
| ↑ ↓ | idle, ⌘K panel | move selection (arrows pass to the text field otherwise) |
| ⌘K | any | open / close the action panel |
| ⌘↩ | approval | Approve once (`AppState.decide(true)`) |
| ⌘⌫ | approval | Deny (`AppState.decide(false)`) |
| ⌘. | running | Stop task (`AppState.cancel`) |
| ⌘C | result, input empty | Copy result (otherwise the text field's copy) |
| ⌘N | result / error | New task (clears result and error) |
| ⌘O | any | Open workspace window |
| ⌘, | any | Settings |
| esc | any | close ⌘K panel, else hide the bar (a running task keeps running; a pending approval stays pending) |
| click outside | any | hide (the panel resigns key) |

Handled by a local `NSEvent` monitor scoped to the panel (`CommandBarController.handle`), covered by
`CommandBarKeyTests`.

## Accessibility

- Every interactive element has a label: the input is "Task request", the chip reads "Model X, On this Mac,
  managed by your organization", key hints read "Run, ↩", the argument block is "Tool arguments", the result is
  "Result". Section headers carry `.isHeader`; selected rows carry `.isSelected`.
- Focus order: input first (focused on every show), then suggestion/approval controls, then the footer hints
  (which are not focusable). The ⌘K panel is a contained element named "Actions".
- The mark and progress bar are hidden from VoiceOver; state is conveyed by the status line instead.
- Contrast: text on surface 15.9:1 (light) / 13.9:1 (dark); muted on surface 5.7:1 / 7.1:1; accent on surface
  5.1:1 / 6.5:1; status colors ≥ 4.5:1 in both schemes. White on accent (prominent button) 5.2:1 light,
  and the dark accent uses ink text where it would not pass.
- Reduce Motion and Reduce Transparency: see Motion and Materials. Increase Contrast is not specially handled
  (system fonts and hairlines already darken); noted as future work.

## Verification

`minimodell --render-design-previews <dir>` renders every state (light and dark) with SwiftUI `ImageRenderer`
at 2×. It needs no configuration, model or window and exits. Two things differ from the live panel by
necessity, and the previews say so in their file names' documentation rather than pretending otherwise:
materials render as the opaque `surface` fallback (ImageRenderer cannot draw `NSVisualEffectView`), and the
text field is drawn as static text with a caret. Scroll views become plain stacks. The desktop behind the card is
a flat placeholder.

`minimodell --open-command-bar` shows the bar 0.6 s after launch for launch checks without a keyboard.

## Not in this slice

- Raycast API compatibility, theming, and a history list (explicitly out of scope in #10).
- A hotkey recorder control (the shortcut is typed as text and validated).
- Increase Contrast variants and a light-mode "reversed" mark treatment.
