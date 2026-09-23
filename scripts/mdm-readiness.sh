#!/bin/bash
# Read-only artifact/configuration checks for Jamf or Kandji.
# This does not prove that a profile is installed or effective in a user session.
set -euo pipefail
if [ "$#" -ne 2 ]; then
    printf '%s\n' 'Usage: mdm-readiness.sh /path/App.app /path/policy.json' >&2
    exit 2
fi
app_bundle="$1"
policy_file="$2"
if [ ! -d "$app_bundle" ] || [ ! -x "$app_bundle/Contents/MacOS/minimodell-diagnostics" ]; then
    printf '%s\n' 'Application or diagnostics executable is missing.' >&2
    exit 1
fi
if [ ! -f "$policy_file" ] || [ ! -r "$policy_file" ]; then
    printf '%s\n' 'The explicit policy file is missing or unreadable.' >&2
    exit 1
fi
/usr/bin/codesign --verify --strict "$app_bundle"
"$app_bundle/Contents/MacOS/minimodell-diagnostics" --config "$policy_file"
