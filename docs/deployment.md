# Distribution and optional management

## Individual installs

`scripts/package-app.sh` builds an app with a stable identity and sandbox entitlements. `scripts/package-dmg.sh` builds a release app and a drag-to-Applications disk image. Set `SIGNING_IDENTITY` to your Developer ID Application certificate for distributable signing. Without it, the scripts produce local development artifacts.

A DMG is a transport container; it does not make an app production-ready. Before public distribution, sign all nested code, submit the signed artifact with `xcrun notarytool`, staple the ticket with `xcrun stapler`, and validate Gatekeeper on a clean Mac. No Apple credentials or signing identity are stored in this repository.

## Enterprise installs

Use `scripts/package-pkg.sh` with `SIGNING_IDENTITY` and `INSTALLER_SIGNING_IDENTITY` (Developer ID Installer). The PKG installs the same app into `/Applications`; it does not write per-user preferences or install a privileged daemon.

Generate the policy profile using `scripts/make-profile.py`. Deploy it as a Jamf custom configuration profile and scope it independently from the application. The forced preference is `PolicyJSON`, a JSON string in `org.minimodell.agent`. A missing profile permits personal settings; an invalid forced profile fails closed.

The example profile is unsigned XML for review/import. Do not place API keys, refresh tokens, client secrets, or employee identifiers in it. Use the app's Keychain UI or browser OAuth for credentials.

## Read-only validation through Jamf

Deploy `scripts/jamf-inventory.sh` as an Extension Attribute to report architecture and RAM. Use smart groups for staged rollout (16, 24, 32, 64 GB). Inventory does not run inference or sign employees into services.

For a policy file staged by IT, run:

```sh
/Applications/minimodeLL.app/Contents/MacOS/minimodell-diagnostics --config /path/to/policy.json
```

Exit 0 means schema, endpoint, model reference and bounds checks passed; exit 1 means validation failed. JSON output contains hardware/software metadata and eligible model IDs. It is not a performance benchmark or a server connectivity check. Explicit `--config` avoids confusing root's preferences with a logged-in user's policy. Run without arguments in the intended user's context when assessing that user's managed preferences.

Do not schedule benchmarks or authenticated tool actions as root. Synthetic performance validation belongs in an opt-in user-session runner, with power/thermal conditions recorded. That runner is planned, not implemented.

## Storage

A packaged sandboxed app stores data under its container's Application Support directory, ending in `org.minimodell.agent`. SwiftPM development execution uses the unsandboxed user's Application Support directory. Settings → Audit opens the actual active path. Those two execution modes do not share configuration automatically.

Future shared models should be provisioned as root-owned read-only files, with directories `0755` and model files `0644`. Never use the historical PRD's `chmod 777`. Signed helper model access and managed model deployment require a dedicated implementation and validation pass.

## Supported management paths and evidence

The design supports both Jamf and Iru (formerly Kandji) through standard macOS PKG and forced-preference profile artifacts. Jamf is the first live validation target: the owner has an environment and access to a coworker's focused sandbox is possible. The [Jamf test plan](jamf-test-plan.md) specifies the run before any claim of enrolled-device validation.

Iru (formerly Kandji) is **best-effort and unvalidated**, with no available tenant or sandbox. Its [deployment guide](kandji.md) maps the shared artifacts to Custom Apps, Custom Profiles and optional Custom Scripts using vendor documentation. No Iru API integration is needed by the app.

`scripts/mdm-readiness.sh` accepts an app bundle and an explicit policy JSON path. It performs read-only signature and schema checks and can be invoked by either MDM. It does not validate the effective user profile or notarization; see the provider guide for exit codes and reporting limitations.

| Path | Shared artifacts | Current evidence | Next validation |
| --- | --- | --- | --- |
| Standalone | Native app, local JSON, future production DMG | Packaged sandboxed UI and local fixture | Real runtime and clean-machine distribution |
| Jamf | PKG, forced profile, inventory/readiness scripts | Local artifact/profile checks only | Focused owner/coworker sandbox worksheet |
| Iru (formerly Kandji) | Same PKG/profile, shared readiness script | Official-documentation review and local artifact checks | Best-effort until an actual tenant is available |
