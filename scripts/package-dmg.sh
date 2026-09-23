#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIGURATION=release scripts/package-app.sh
name="$(/usr/bin/plutil -extract displayName raw Sources/LocalAgentCore/Resources/Branding.json)"
version="$(/usr/bin/plutil -extract version raw Sources/LocalAgentCore/Resources/Branding.json)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R "build/$name.app" "$stage/"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "$name" -srcfolder "$stage" -ov -format UDZO "build/$name-$version.dmg"
if [ -n "${SIGNING_IDENTITY:-}" ]; then
    codesign --sign "$SIGNING_IDENTITY" "build/$name-$version.dmg"
fi
