#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-debug}"
swift build -c "$configuration"
bin_path="$(swift build -c "$configuration" --show-bin-path)"
brand_file="Sources/LocalAgentCore/Resources/Branding.json"
display_name="$(/usr/bin/plutil -extract displayName raw "$brand_file")"
bundle_id="$(/usr/bin/plutil -extract bundleIdentifier raw "$brand_file")"
version="$(/usr/bin/plutil -extract version raw "$brand_file")"
app_path="$PWD/build/$display_name.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_path/minimodell" "$app_path/Contents/MacOS/minimodell"
cp "$bin_path/minimodell-diagnostics" "$app_path/Contents/MacOS/minimodell-diagnostics"
# Packaged app and diagnostics resolve this before the SwiftPM development resource.
cp "$brand_file" "$app_path/Contents/Resources/Branding.json"
# Curated resources shared with SwiftPM; do not place unsealed bundles at the app root.
cp -R Sources/MinimodeLL/Resources/BrandAssets "$app_path/Contents/Resources/"
cp Sources/MinimodeLL/Resources/BrandAssets/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
mkdir -p "$app_path/Contents/Resources/Licenses"
install -m 644 LICENSE "$app_path/Contents/Resources/Licenses/minimodell.txt"
install -m 644 .build/checkouts/swift-sdk/LICENSE "$app_path/Contents/Resources/Licenses/mcp-swift-sdk.txt"
install -m 644 .build/checkouts/swift-log/LICENSE.txt "$app_path/Contents/Resources/Licenses/swift-log.txt"
install -m 644 .build/checkouts/swift-system/LICENSE.txt "$app_path/Contents/Resources/Licenses/swift-system.txt"
install -m 644 .build/checkouts/eventsource/LICENSE.md "$app_path/Contents/Resources/Licenses/eventsource.txt"
/usr/bin/python3 - "$app_path/Contents/Info.plist" "$display_name" "$bundle_id" "$version" <<'PY'
import plistlib, sys
path, name, identifier, version = sys.argv[1:]
with open(path, 'wb') as f:
    plistlib.dump({
        'CFBundleName': name, 'CFBundleDisplayName': name,
        'CFBundleIdentifier': identifier, 'CFBundleExecutable': 'minimodell',
        'CFBundleIconFile': 'AppIcon.icns',
        'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': version,
        'CFBundleVersion': '1', 'LSMinimumSystemVersion': '14.0',
        'LSUIElement': True, 'NSHighResolutionCapable': True,
        'CFBundleURLTypes': [{'CFBundleURLName': identifier, 'CFBundleURLSchemes': [identifier]}],
        'NSAppTransportSecurity': {'NSAllowsLocalNetworking': True},
    }, f)
PY
identity="${SIGNING_IDENTITY:--}"
codesign --force --options runtime --sign "$identity" "$app_path/Contents/MacOS/minimodell-diagnostics"
codesign --force --options runtime --entitlements packaging/App.entitlements --sign "$identity" "$app_path"
codesign --verify --strict "$app_path"
printf '%s\n' "$app_path"
