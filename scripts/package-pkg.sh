#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIGURATION=release scripts/package-app.sh
name="$(/usr/bin/plutil -extract displayName raw Sources/LocalAgentCore/Resources/Branding.json)"
version="$(/usr/bin/plutil -extract version raw Sources/LocalAgentCore/Resources/Branding.json)"
identifier="$(/usr/bin/plutil -extract bundleIdentifier raw Sources/LocalAgentCore/Resources/Branding.json)"
args=()
if [ -n "${INSTALLER_SIGNING_IDENTITY:-}" ]; then args+=(--sign "$INSTALLER_SIGNING_IDENTITY"); fi
pkgbuild --component "build/$name.app" --install-location /Applications --identifier "$identifier" --version "$version" "${args[@]}" "build/$name-$version.pkg"
