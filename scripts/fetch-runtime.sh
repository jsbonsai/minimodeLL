#!/bin/bash
# Fetch the pinned llama.cpp llama-server prebuilt described by packaging/runtime.lock.json.
#
# - Downloads only the pinned official ggml-org/llama.cpp release asset over HTTPS.
# - Verifies byte size and SHA-256 BEFORE extracting anything.
# - Copies only llama-server, its @rpath dylib closure, and the upstream LICENSE into
#   vendor/llama.cpp/<tag>/ (gitignored). Nothing here is ever committed.
# - Fails if the upstream dependency closure differs from the lock file, or if any binary
#   links a non-system absolute path (for example Homebrew), or is not arm64.
#
# Usage: scripts/fetch-runtime.sh            # idempotent; reuses a verified vendor copy
#        FORCE=1 scripts/fetch-runtime.sh    # re-download and re-verify
#        RUNTIME_LOCK=/path/lock.json ...    # alternate lock (used to test checksum rejection)
set -euo pipefail
cd "$(dirname "$0")/.."
lock="${RUNTIME_LOCK:-packaging/runtime.lock.json}"

read_lock() { /usr/bin/python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))[sys.argv[2]]; print("\n".join(v) if isinstance(v, list) else v)' "$lock" "$1"; }
tag="$(read_lock tag)"
url="$(read_lock url)"
asset="$(read_lock asset)"
expected_sha="$(read_lock sha256)"
expected_size="$(read_lock sizeBytes)"
executable="$(read_lock executable)"
license_file="$(read_lock licenseFile)"
expected_libs="$(read_lock libraries | LC_ALL=C sort)"

case "$url" in
  "https://github.com/ggml-org/llama.cpp/releases/download/$tag/$asset") ;;
  *) echo "error: lock URL is not the official pinned ggml-org release asset" >&2; exit 1 ;;
esac

dest="vendor/llama.cpp/$tag"
marker="$dest/runtime.lock.json"
if [[ -z "${FORCE:-}" && -f "$marker" ]] && cmp -s "$marker" "$lock"; then
  echo "Runtime $tag already fetched and verified at $dest"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
echo "Downloading $asset"
curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 -o "$work/$asset" "$url"

actual_size="$(stat -f %z "$work/$asset")"
actual_sha="$(shasum -a 256 "$work/$asset" | awk '{print $1}')"
if [[ "$actual_size" != "$expected_size" || "$actual_sha" != "$expected_sha" ]]; then
  echo "error: checksum mismatch for $asset (size $actual_size, sha256 $actual_sha); refusing to extract" >&2
  exit 1
fi
echo "Verified SHA-256 $actual_sha"

mkdir -p "$work/x"
tar -xzf "$work/$asset" -C "$work/x"
src="$work/x/llama-$tag"
[[ -x "$src/$executable" ]] || { echo "error: $executable missing from archive" >&2; exit 1; }

# Walk the @rpath closure starting at the server executable.
closure=()
queue=("$src/$executable")
while ((${#queue[@]})); do
  current="${queue[0]}"; queue=("${queue[@]:1}")
  while read -r dep; do
    case "$dep" in
      @rpath/*)
        name="${dep#@rpath/}"
        if [[ ! " ${closure[*]:-} " == *" $name "* ]]; then
          [[ -e "$src/$name" ]] || { echo "error: $name missing from archive" >&2; exit 1; }
          closure+=("$name"); queue+=("$src/$name")
        fi ;;
      /usr/lib/*|/System/Library/*) ;;
      *) echo "error: $(basename "$current") links non-system path $dep" >&2; exit 1 ;;
    esac
  done < <(otool -L "$current" | tail -n +2 | awk '{print $1}')
done
actual_libs="$(printf '%s\n' "${closure[@]}" | LC_ALL=C sort)"
if [[ "$actual_libs" != "$expected_libs" ]]; then
  echo "error: upstream dylib closure differs from $lock" >&2
  diff <(echo "$expected_libs") <(echo "$actual_libs") >&2 || true
  exit 1
fi

rm -rf "$dest"; mkdir -p "$dest"
install -m 755 "$src/$executable" "$dest/$executable"
for name in "${closure[@]}"; do
  # Resolve upstream version symlinks; the install name (@rpath/<name>) is what dyld looks up.
  cp -L "$src/$name" "$dest/$name"; chmod 755 "$dest/$name"
done
install -m 644 "$src/$license_file" "$dest/LICENSE"
for binary in "$dest/$executable" "$dest"/*.dylib; do
  [[ "$(lipo -archs "$binary")" == "arm64" ]] || { echo "error: $binary is not arm64-only" >&2; exit 1; }
done
grep -q "MIT License" "$dest/LICENSE" || { echo "error: unexpected upstream license text" >&2; exit 1; }
cp "$lock" "$marker"
echo "Runtime $tag ready at $dest"
