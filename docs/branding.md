# Brand asset integration

The owner supplied `design-assets/` on 2026-09-23. Original artwork and the kit README are retained as supplied. The macOS app uses a curated resource subset so website/social assets and duplicate masters do not inflate the executable bundle.

## Source and runtime mapping

| Brand kit source | Runtime use |
| --- | --- |
| `app-icon/AppIcon.icns` | Contents/Resources/AppIcon.icns; Info.plist CFBundleIconFile |
| `menubar/png/*Template*.png` | 18-point template NSImages with 1x/2x/3x representations; macOS performs tinting |
| `swift/MinimodeMark.swift` | Adapted as an internal SwiftUI view in the app target, preserving supplied geometry |
| `xcode/Assets.xcassets/*.colorset/Contents.json` | Adaptive light/dark palette decoded from supplied RGB/hex components |
| `fonts/Geist-Regular.otf`, `Geist-Bold.otf`, `Geist-SemiBold.otf` | Wordmark, body/result and empty-state typography |
| `fonts/GeistMono-Regular.otf` | Configuration and tool-argument text |
| `fonts/OFL.txt` | Bundled SIL Open Font License |
| `tokens/tokens.json` | Retained with runtime assets as the supplied token reference |

Native control labels and some hierarchy styles retain system fonts. Brand fonts are registered for the process with CoreText; no system-wide font install occurs. The wordmark is generated from `Brand.displayName`, with a trailing LL accented when present, preserving easy renaming. Static icon artwork still needs replacement when changing visual identity.

`BrandAssets.swift` prefers Contents/Resources/BrandAssets in the packaged app and falls back to the SwiftPM resource bundle in development. This avoids the previously observed unsealed-app-root signing problem. Raw template PNGs and color definitions are used so command-line SwiftPM builds need no Xcode asset-catalog project. Original vector/catalog masters remain in the kit for future tooling.

## Status semantics in this preview

The supplied artwork describes a future server lifecycle. This app does not observe server health yet, so the current mapping is explicitly application state:

- Solid dot: a task is in progress.
- Ring dot: valid configuration, no task in progress.
- No dot: configuration unavailable/invalid.

These states do not certify that llama-server is running or a model is loaded. WORK-001 should revisit the mapping when actual runtime health is observable. The idle mark also appears decoratively in the empty result area. Colors adapt to system appearance; no user appearance setting is changed.

## Update assets

```sh
python3 scripts/sync-brand-assets.py
scripts/package-app.sh
open build/minimodeLL.app
```

The sync command refreshes the checked-in runtime subset from the original kit. Run it when artwork/fonts/colors change and review the resulting Git diff. It does not overwrite the adapted SwiftUI source. The supplied `MinimodeMark` source uses app-internal visibility and the resource-backed palette; update it deliberately if logo geometry changes.

The app's menu bar images are cached on the main actor, sized to 18 points and marked as templates. The palette parser expects the checked-in catalog JSON structure; malformed brand resources are a build/review error, not a user configuration feature.

## Design tokens in code

`Sources/MinimodeLL/Design/Tokens.swift` maps `tokens/tokens.json` and `brand.css` to a `DesignPalette` per color scheme (paper/ink surfaces, graphite/mist, Signal and Signal Dark, status colors lightened in dark mode for contrast), plus spacing, radii and the Geist type ramp. The command bar and the restyled Settings window read these through the SwiftUI environment (`designRoot()`); `BrandAssets.color` remains for the workspace's `NSAppearance`-driven colors. The mapping table is in `docs/design/raycast-redesign.md`.

## Validation

The packaged app builds and passes strict signature verification, restarts successfully, and its branded workspace was visually inspected on the development Mac in dark appearance. Supplied app-icon metadata and resource bytes were checked in the bundle. Light appearance, active/off status appearance and Finder cache behavior have not received separate visual verification in this session. Core inference/policy behavior was not changed.
