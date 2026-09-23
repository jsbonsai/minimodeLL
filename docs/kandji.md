# Kandji deployment — best-effort, unvalidated

Status as of 2026-09-23: design and documentation support only. The owner has no Kandji tenant or sandbox. No application install, profile delivery, script execution or effective managed-preference behavior has been tested in Kandji. Do not describe this integration as certified or fleet validated.

## Shared management contract

Kandji and Jamf use the same app, signed PKG, schema-version-1 policy and generated `.mobileconfig`. Neither provider has an SDK or credential in the app. The app reads macOS forced preferences; the MDM vendor delivers them. Support therefore means maintaining portable artifacts and provider-specific instructions, with separate evidence for each provider.

The app preference domain defaults to `org.minimodell.agent`, and the forced value is `PolicyJSON`, a JSON string. Profiles replace the full app policy. Models, LiteLLM aliases, MCP server definitions and limits use the shared [configuration reference](configuration-reference.md). Credentials remain in the user's Keychain/browser OAuth flow, never in MDM policy.

## Proposed deployment workflow

1. Build and validate the app/package following [deployment](deployment.md). For production, use Developer ID and notarization; an ad-hoc development artifact is not a public distribution release.
2. Add a **Custom App** Library Item and upload the PKG. Kandji documents support for PKG, DMG and ZIP installers. Use the existing app's bundle identifier and verify version/detection behavior in a narrow test Blueprint before wider assignment. Use the PKG path for parity with Jamf. Kandji documents that a DMG should contain only the app; our drag-to-Applications DMG also includes an Applications link and is not the recommended Kandji upload. [Kandji Custom Apps](https://support.kandji.io/kb/deploying-custom-apps)
3. Validate a reviewed policy with the diagnostics CLI, generate the `.mobileconfig`, and add it as a **Custom Profile** Library Item. Assign the application and profile to the same small test population using the organization's Blueprint workflow. Verify that the uploaded payload preserves the forced preference string/domain. [Kandji Custom Profiles](https://support.kandji.io/kb/custom-profiles-overview)
4. Launch the app in the enrolled user's session and verify that it shows managed configuration and disables policy editing. Check an approved model alias and a denied local override. Root execution of a script does not prove this behavior.
5. If script-based readiness is desired, deploy the shared `scripts/mdm-readiness.sh` plus a reviewed, credential-free policy JSON to controlled paths, then invoke it with the installed app and explicit policy path. Use an audit-only Custom Script; do not configure automatic remediation around preview failures. Kandji records stdout/stderr in audit information, so keep output content-free. [Kandji Custom Scripts](https://support.kandji.io/kb/custom-scripts-overview)
6. Test updates, invalid policy, removal, rollback and user-session behavior with the same acceptance criteria as the Jamf test plan. Record actual results in a new validation record, not by changing the support label based on artifact lint alone.

## Readiness check semantics

```sh
/path/to/mdm-readiness.sh /Applications/minimodeLL.app /path/to/reviewed-policy.json
```

Exit 0: app signature verifies and the explicit policy passes the shared validator. Exit 1: missing artifact/config, signature failure, or policy validation failure. Exit 2: usage error. CLI JSON includes hardware/software metadata and eligible model IDs. An ad-hoc signature can pass this check; it is not a notarization or certificate-trust assessment.

The report's `managed` value is false when using `--config` because it validates that explicit file, not effective user preferences. This is intentional and must not be interpreted as evidence that the device is unmanaged. The check does not contact a model, authenticate MCP, or certify profile delivery.

## Unknowns requiring a real tenant

- Profile import behavior and any payload rewriting.
- Blueprint assignment timing and app/profile installation order.
- Custom App detection, update/reinstall and uninstall behavior for this bundle.
- Custom Script execution context, selected scheduling mode and reporting presentation.
- Actual forced preference precedence inside the sandboxed app, including malformed/removal cases.
- User OAuth/Keychain behavior after MDM installation and updates.

Do not work around an installation failure by stripping quarantine or disabling Gatekeeper. Diagnose signing/notarization and validate the supported distribution path. No Kandji API integration or automatic tenant configuration is implemented or required.

## Vendor documentation freshness

The official Kandji pages consulted on 2026-09-23 display a migration notice to Iru with a December 1, 2026 deadline. Keep the requested Kandji terminology for this support path, but recheck current vendor/tenant workflows before the first deployment. The shared macOS artifact contract avoids coupling the app to either branding or a vendor API.
