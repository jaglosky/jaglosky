#!/usr/bin/env bash
# release-check with a client-supplied Android binary (instead of building one):
# an APK is used as is; an AAB becomes a universal APK via bundletool, signed with the throwaway CI key
# (the same key `jaglosky verify --release` uses), so it installs on the emulator.
# Usage: fetch-binary.sh <https URL> <out dir>   — writes run-dir / apk / binary / outcome to $GITHUB_OUTPUT.
set -euo pipefail
URL="$1"
OUT="$2"
mkdir -p "$OUT"
TMP="$(mktemp -d)"
curl -fsSL --retry 3 "$URL" -o "$TMP/binary" || { echo "::error::Could not download binary-url (it must be a direct https link)"; exit 1; }

if unzip -l "$TMP/binary" 2>/dev/null | grep -q " BundleConfig.pb$"; then
  KIND=AAB
elif unzip -l "$TMP/binary" 2>/dev/null | grep -q " AndroidManifest.xml$"; then
  KIND=APK
else
  echo "::error::binary-url is neither an APK nor an AAB"
  exit 1
fi

if [ "$KIND" = APK ]; then
  cp "$TMP/binary" "$OUT/app-release.apk"
else
  KS="$HOME/.jaglosky/ci-release-check.keystore"
  mkdir -p "$(dirname "$KS")"
  [ -f "$KS" ] || keytool -genkeypair -keystore "$KS" -storepass jaglosky-ci -keypass jaglosky-ci -alias jaglosky-ci \
    -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Jaglosky release check" > /dev/null
  gh release download --repo google/bundletool --pattern 'bundletool-all-*.jar' --dir "$TMP" --clobber
  java -jar "$(ls "$TMP"/bundletool-all-*.jar | head -1)" build-apks --bundle "$TMP/binary" --output "$TMP/app.apks" \
    --mode universal --ks "$KS" --ks-pass pass:jaglosky-ci --ks-key-alias jaglosky-ci --key-pass pass:jaglosky-ci
  unzip -o -q "$TMP/app.apks" universal.apk -d "$TMP"
  cp "$TMP/universal.apk" "$OUT/app-release.apk"
fi

echo "Client-supplied $KIND → $OUT/app-release.apk ($(du -h "$OUT/app-release.apk" | cut -f1))"
{
  echo "run-dir=$OUT"
  echo "apk=$OUT/app-release.apk"
  echo "binary=client-supplied $KIND"
  echo "outcome=green"
} >> "$GITHUB_OUTPUT"
