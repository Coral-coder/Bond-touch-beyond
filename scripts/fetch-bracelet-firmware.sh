#!/usr/bin/env bash
# Bundles the official Bond Touch bracelet firmware into the app at build time, so a
# bracelet stuck in update mode is repaired automatically with no user steps.
#
# The firmware belongs to Impossible Labs, so it is never committed to this public
# repository: this script takes it from the official Bond Touch Android package
# (com.impossible.bondtouch, versionCode 490, which ships the same firmware as the iOS
# app), identifies each file by its pinned SHA-256, and writes them to Firmware/
# (git-ignored), which the app target bundles if present. CI caches the folder, so the
# package is downloaded once. If anything fails, the build continues without bundled
# firmware (the app can still import a file by hand).
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/Firmware"
PACKAGE=com.impossible.bondtouch
VERSION_CODE=490

# sha256 → bundled name (BraceletModel raw value, variants suffixed). A function, not
# an associative array, so it runs on macOS's bash 3.2 too.
NAMES="bondTouchMore bondTouch bondTouch-hw203 bondTouch4 bondMini"
name_for() {
  case "$1" in
    e99e2080e780714d208e553cb817a8d92f1bbc179a381977c156d5bedf7cae22) echo bondTouchMore ;;    # dfu_v311_hw3g  (Bond Touch More 3.1.1)
    0b5cbbc8ff65dfc052991782fab79772d15d7ccd1018e62255e3ca8cb5cffa99) echo bondTouch ;;        # dfu_v279_hw2g  (Bond Touch 2.7.9)
    27cc927b1b3cf2e804065f297accdc6a99ee6529d8f90cfceeb0c64e87c1ed7b) echo bondTouch-hw203 ;;  # dfu_v260_hw203 (Bond Touch 2.6.0, older hardware)
    75080bd388fab0e0995340513e4431d9ebeac8ce74536a40a0482e587e8b45b8) echo bondTouch4 ;;       # dfu_v203_hw4g  (Bond Touch 4 2.0.3)
    8da75cec34a227773ea11cc2c089394e16049bcf374351faa40c2adc21bc2068) echo bondMini ;;         # dfu_v120_hwmini (Bond Mini 1.2.0)
  esac
}

have_all() { for n in $NAMES; do [ -f "$dest/$n.zip" ] || return 1; done; return 0; }
if have_all; then echo "Bracelet firmware already present"; exit 0; fi

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
ua="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36"
query="versionCode=${VERSION_CODE}&nc=armeabi-v7a&sv=29"

fetch() {
  local code
  code=$(curl -sS -L --retry 2 --connect-timeout 20 -A "$ua" -H "Accept: */*" -o "$work/pkg" -w '%{http_code}' "$1" || echo 000)
  echo "  $1 → HTTP $code"
  [ "$code" = 200 ] && [ "$(head -c 2 "$work/pkg" 2>/dev/null)" = "PK" ]
}

ok=
# LOCAL_PACKAGE=path uses an already-downloaded package (for testing).
if [ -n "${LOCAL_PACKAGE:-}" ] && cp "$LOCAL_PACKAGE" "$work/pkg"; then ok=1; fi
for kind in XAPK APK; do
  [ -n "$ok" ] && break
  for host in d.apkpure.com download.pureapk.com; do
    if fetch "https://${host}/b/${kind}/${PACKAGE}?${query}"; then ok=1; break 2; fi
  done
done
if [ -z "$ok" ]; then
  curl -sS -L --compressed --retry 2 -A "okhttp/4.9.3" -H "x-cv: 3172501" -H "x-sv: 29" \
    -H "x-abis: armeabi-v7a,armeabi" -H "x-gp: 1" -o "$work/versions.bin" \
    "https://api.pureapk.com/m/v3/cms/app_version?hl=en-US&package_name=${PACKAGE}" || true
  while read -r link; do
    fetch "$link" && { ok=1; break; }
  done < <(grep -aoE 'https?://[A-Za-z0-9.-]+/b/(XAPK|APK)/[^[:space:][:cntrl:]"]+' "$work/versions.bin" 2>/dev/null | awk '!seen[$0]++')
fi
if [ -z "$ok" ]; then
  echo "::warning::Couldn't download the official Bond Touch package; building without bundled bracelet firmware."
  exit 0
fi

# An XAPK holds the base APK; an APK is the base itself.
mkdir -p "$work/apk" "$work/fw"
if unzip -l "$work/pkg" "${PACKAGE}.apk" >/dev/null 2>&1; then
  unzip -q -o "$work/pkg" "${PACKAGE}.apk" -d "$work/apk" && base="$work/apk/${PACKAGE}.apk"
else
  base="$work/pkg"
fi
# Take every .zip inside the APK and keep the ones whose fingerprint is pinned above.
unzip -q -o "$base" '*.zip' -d "$work/fw" 2>/dev/null || true
mkdir -p "$dest"
found=0
while IFS= read -r -d '' f; do
  sum=$(shasum -a 256 "$f" 2>/dev/null | awk '{print $1}' || sha256sum "$f" | awk '{print $1}')
  name="$(name_for "$sum")"
  if [ -n "$name" ]; then cp "$f" "$dest/$name.zip"; found=$((found + 1)); echo "  bundled $name ($(basename "$f"))"; fi
done < <(find "$work/fw" -name '*.zip' -print0)
echo "Bracelet firmware files bundled: $found of 5"
[ "$found" -gt 0 ] || echo "::warning::No pinned firmware found in the package; building without it."
exit 0
