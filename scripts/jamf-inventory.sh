#!/bin/bash
# Jamf Extension Attribute: read-only hardware eligibility, no inference or user content.
set -euo pipefail
memory_bytes="$(/usr/sbin/sysctl -n hw.memsize)"
memory_gb=$((memory_bytes / 1073741824))
architecture="$(/usr/bin/uname -m)"
printf '<result>%s; %s GB</result>\n' "$architecture" "$memory_gb"
