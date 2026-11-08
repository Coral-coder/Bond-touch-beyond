#!/usr/bin/env bash
# Downloads Signal's prebuilt libsignal_ffi.a for iOS (the Rust core behind LibSignalClient),
# pinned to the exact version of the vendored Swift sources in ThirdParty/LibSignalClient and
# verified by SHA-256. Same archive Signal's own podspec fetches. Extracts to
# ThirdParty/libsignal-ffi/target/<triple>/release/libsignal_ffi.a (git-ignored, ~100 MB).
set -euo pipefail

VERSION="0.86.5"
SHA256="a3df979aa39b307ac4ef0f3fd59536daab5d6b3f8257c7aefe5f0470625f2582"
URL="https://build-artifacts.signal.org/libraries/libsignal-client-ios-build-v${VERSION}.tar.gz"

root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/ThirdParty/libsignal-ffi"
stamp="$dest/.version"

if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$VERSION" ] \
   && [ -f "$dest/target/aarch64-apple-ios/release/libsignal_ffi.a" ]; then
  echo "libsignal_ffi $VERSION already present"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "Downloading libsignal_ffi $VERSION"
curl -fsSL --retry 3 -o "$tmp/ffi.tar.gz" "$URL"
actual="$(shasum -a 256 "$tmp/ffi.tar.gz" | awk '{print $1}')"
if [ "$actual" != "$SHA256" ]; then
  echo "::error::libsignal_ffi checksum mismatch: expected $SHA256, got $actual" >&2
  exit 1
fi
rm -rf "$dest"
mkdir -p "$dest"
tar -xzf "$tmp/ffi.tar.gz" -C "$dest"
echo "$VERSION" > "$stamp"
ls -la "$dest"/target/*/release/libsignal_ffi.a
