# Development and recovery runbook

## Prerequisites and checkout

The initial environment is Apple Silicon with Xcode 16.4, Swift 6.1.2 and macOS 15.7.7. Minimum declared app OS is macOS 14. The package targets Swift 6.1. Use the repository's resolved dependency file; record intentional upgrades.

```sh
git status --short
git log -5 --oneline
swift --version
xcodebuild -version
swift package resolve
swift test
```

The XCTest wrapper can print “Executed 0 tests” before Swift Testing runs. Read the final Swift Testing summary; the baseline has 16 tests. Do not interpret that wrapper line as no tests having run.

## Build and run modes

```sh
swift run minimodell
scripts/package-app.sh
open build/minimodeLL.app
```

The first command is unsandboxed development execution. The packaged `.app` enables sandbox and Hardened Runtime and is the meaningful path for packaging, Keychain, preferences and filesystem checks. Close the running app before replacing its executable. The app can remain in the menu bar after its task window closes; quit it explicitly when rebuilding for a launch check.

The command bar (`docs/design/raycast-redesign.md`) opens with ⌥Space by default (Settings → Command Bar). Three debug arguments help when no keyboard automation is available: `minimodell --open-command-bar` shows the bar shortly after launch, `minimodell --open-workspace` opens the workspace window through the bar's ⌘O path (proves the opener works before any window exists), and `minimodell --render-design-previews <dir>` writes PNGs of every bar state (light and dark) with `ImageRenderer` and exits. The renderer must run from the SwiftPM build (`.build/debug/minimodell`): the sandboxed `.app` cannot write outside its container. Materials render opaque and the text field as static text in those PNGs; only a launched app shows real vibrancy. `screencapture -l` of the panel needs Screen Recording permission and fails with "could not create image from window" without it.

Generated files under `.build/` and `build/` are not committed. A new agent on another machine must build them. Never assume a link to a previous local `.app` means a GitHub release exists.

## UI connectivity without a model or account

In a terminal:

```sh
python3 scripts/mock-inference.py
```

Open the packaged app with the default local configuration and submit a synthetic request. Expect a response explicitly beginning “Fixture response”. This verifies the UI → policy → HTTP → result path only. No language model, MCP tool or OAuth server participates. Stop the fixture with Ctrl-C before starting a real server on port 9931. Do not leave it running during model qualification or report its response as generated inference.

## Actual local inference

No selected model, GGUF or llama-server binary is part of the checkout. The current README shows how to start an externally supplied runtime using the alias `local-model`. Before real qualification, record runtime revision, model source/license/hash, quantization, chat template and context settings. Keep company content out of public fixtures.

A server may load memory independently of this app's checks. The preview does not own its lifecycle. The bundled-runtime backlog item must address this before enterprise rollout.

## Configuration diagnostics and profile generation

```sh
swift run minimodell-diagnostics --config Config/local.example.json
swift run minimodell-diagnostics --config Config/enterprise.example.json
scripts/make-profile.py Config/enterprise.example.json build/minimodell.mobileconfig
plutil -lint build/minimodell.mobileconfig
```

Diagnostics does not contact endpoints or validate that aliases exist. The profile generator alone does not validate policy semantics. When running as root through Jamf, supply the intended explicit policy file rather than treating root's user preferences as an employee's effective settings.

## Signing and distribution tooling

```sh
codesign --verify --strict build/minimodeLL.app
codesign -d --entitlements - build/minimodeLL.app
```

`CONFIGURATION=release scripts/package-app.sh` creates a release-mode app. `SIGNING_IDENTITY` supplies a Developer ID Application identity; default `-` means ad-hoc. `INSTALLER_SIGNING_IDENTITY` is used only by the PKG script. The scripts do not submit to notarization or manage credentials.

DMG/PKG scripts are present but not yet clean-machine installation evidence. Do not attach development binaries to a production GitHub release. Model/runtime redistribution also needs license and artifact integrity review.

## Known failure recovery

- **Own-domain UserDefaults initialization:** use `.standard` in the packaged app; the explicit suite is for a differently identified process. The earlier force-unwrap crash is fixed.
- **Unsealed bundle root:** do not put SwiftPM resource bundles at the `.app` root. Branding belongs in Contents/Resources; use the existing lookup logic.
- **License copy permission failures:** checkout license files may be read-only. Packaging uses `install -m 644` for copies so repeated builds can replace them.
- **Configuration appears different between launches:** check whether the process is SwiftPM or the sandboxed bundle; they use different support directories.
- **Settings show an invalid configuration:** correct the local JSON through the settings editor or local support path. Invalid managed JSON must be fixed in MDM; the app must not fall back around it.
- **Connection refused:** check the selected endpoint and whether a real server or intentional fixture is running. Do not switch the task to cloud automatically.
- **Context rejected before inference:** selected schemas and prior tool results count too. Narrow tools/results rather than removing the guard.
- **OAuth repeatedly opens sign-in:** check public client registration, callback, endpoint identity and Keychain persistence; do not place a client secret in JSON as a workaround.

## GitHub workflow

Use `gh auth status` without printing token values. Read the current branch/remote before pushing. For new work, create a focused branch, keep documents beside implementation changes, push, and open a PR with the concrete behavior and validation. Watch the relevant CI run once; investigate failures before claiming completion. Use `--body-file` for multiline issue/PR text.

Keep public docs, examples and issues free of private service URLs, employee data, Keychain contents and logs containing content. Prefer references to stable repo files over transient absolute developer-machine paths in committed documentation.
