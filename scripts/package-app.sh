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
# Remove previously embedded runtime so an absent runtime never leaves a stale helper behind.
rm -rf "$app_path/Contents/Helpers" "$app_path/Contents/Frameworks" "$app_path/Contents/Resources/Runtime" \
  "$app_path/Contents/Resources/Licenses/llama.cpp.txt"
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
# Optional pinned llama.cpp runtime (scripts/fetch-runtime.sh). Absent → external-server mode only.
runtime_tag="$(/usr/bin/python3 -c 'import json; print(json.load(open("packaging/runtime.lock.json"))["tag"])')"
runtime_dir="vendor/llama.cpp/$runtime_tag"
embed_runtime=0
if [[ -f "$runtime_dir/runtime.lock.json" ]] && cmp -s "$runtime_dir/runtime.lock.json" packaging/runtime.lock.json; then
  embed_runtime=1
  mkdir -p "$app_path/Contents/Helpers" "$app_path/Contents/Frameworks" "$app_path/Contents/Resources/Runtime"
  install -m 755 "$runtime_dir/llama-server" "$app_path/Contents/Helpers/llama-server"
  for lib in "$runtime_dir"/*.dylib; do install -m 755 "$lib" "$app_path/Contents/Frameworks/"; done
  # Resolve @rpath only from the app's Frameworks directory, never from next to the helper.
  install_name_tool -delete_rpath @loader_path "$app_path/Contents/Helpers/llama-server"
  install_name_tool -add_rpath @executable_path/../Frameworks "$app_path/Contents/Helpers/llama-server"
  install -m 644 "$runtime_dir/LICENSE" "$app_path/Contents/Resources/Licenses/llama.cpp.txt"
  install -m 644 packaging/runtime.lock.json "$app_path/Contents/Resources/Runtime/runtime.lock.json"
elif [[ -n "${REQUIRE_RUNTIME:-}" ]]; then
  echo "error: REQUIRE_RUNTIME is set but $runtime_dir is missing; run scripts/fetch-runtime.sh" >&2
  exit 1
else
  echo "note: bundled runtime not fetched; packaging external-server mode only" >&2
fi
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
# Sign nested code inside-out: runtime dylibs, sandbox-inheriting helper, diagnostics, then the app.
if ((embed_runtime)); then
  for lib in "$app_path/Contents/Frameworks"/*.dylib; do
    codesign --force --options runtime --sign "$identity" "$lib"
  done
  codesign --force --options runtime --entitlements packaging/Helper.entitlements --sign "$identity" \
    "$app_path/Contents/Helpers/llama-server"
fi
codesign --force --options runtime --sign "$identity" "$app_path/Contents/MacOS/minimodell-diagnostics"
codesign --force --options runtime --entitlements packaging/App.entitlements --sign "$identity" "$app_path"
codesign --verify --strict "$app_path"
printf '%s\n' "$app_path"
