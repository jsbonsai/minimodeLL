# ADR 0007: Central branding and separate distribution formats

Date: 2026-09-23. Status: Accepted; production distribution pending.

## Context

The working name changed from minimodel to minimodeLL. The owner wants quick future renaming and open-source distribution, with optional Jamf deployment. A disk image was suggested for the production app.

## Decision

Store display name, version and bundle identity in one branding JSON resource. Keep identity stable after deployment because it anchors Keychain, preferences, callbacks and storage. Build one native app. Use a DMG for individual drag-to-Applications installs and a PKG for managed installation; distribute policy separately. Use MIT for project source, preserving separate dependency/model licensing.

## Alternatives and consequences

Renaming every identifier with the display name would orphan data and registrations. Combining company configuration, app executable and model weights into one monolithic installer would make routine updates expensive. The preview therefore ships neither GGUFs nor an inference binary yet; future runtime and model packaging require explicit integrity/licensing decisions.

Development builds are ad-hoc signed with App Sandbox and Hardened Runtime. A DMG or PKG does not establish production readiness. Developer ID signing, nested helper signatures, notarization/stapling, clean-machine installation, updates and rollback remain gates.

## Packaging discoveries

SwiftPM's default resource lookup expected a bundle at the app root, but macOS strict signing rejected unsealed root contents. Packaged branding is now under Contents/Resources with explicit lookup before the SwiftPM fallback. Diagnostics has a compatible resource path. Third-party notices are installed with writable build-file permissions to permit repeat packaging from read-only checkout license files.
