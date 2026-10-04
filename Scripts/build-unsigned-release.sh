#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${TMPDIR:-/tmp}/DisplayCove-Unsigned-Release-DerivedData"
KEYCHAIN="${DISPLAYCOVE_SIGNING_KEYCHAIN:-}"
IDENTITY="${DISPLAYCOVE_SIGNING_IDENTITY:--}"
TAG="${DISPLAYCOVE_RELEASE_TAG:-v1.0.0}"
APP="$DERIVED_DATA/Build/Products/Release/DisplayCove.app"
ENTITLEMENTS="$DERIVED_DATA/DisplayCove-Unsigned.entitlements"
STAGING="$DERIVED_DATA/DisplayCove-Unsigned"
DIST="$ROOT/dist/$TAG"

cd "$ROOT"
rm -rf "$DERIVED_DATA" "$DIST"
mkdir -p "$DIST"

SIGNING_ARGUMENTS=(
  --force
  --sign "$IDENTITY"
  --options runtime
)
if [[ -n "$KEYCHAIN" ]]; then
  SIGNING_ARGUMENTS+=(--keychain "$KEYCHAIN")
fi

xcodebuild -quiet \
  -project DisplayCove.xcodeproj \
  -scheme DisplayCove \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

while IFS= read -r -d '' file; do
  if file "$file" | grep -q "Mach-O"; then
    codesign "${SIGNING_ARGUMENTS[@]}" "$file"
  fi
done < <(find "$APP" -type f -perm -111 -print0)

cp DisplayCove/DisplayCove.entitlements "$ENTITLEMENTS"
/usr/libexec/PlistBuddy \
  -c "Set :com.apple.security.temporary-exception.mach-lookup.global-name:1 dev.juma.DisplayCove-spks" \
  -c "Set :com.apple.security.temporary-exception.mach-lookup.global-name:2 dev.juma.DisplayCove-spki" \
  "$ENTITLEMENTS"
/usr/libexec/PlistBuddy \
  -c "Add :com.apple.security.cs.disable-library-validation bool true" \
  "$ENTITLEMENTS"

codesign \
  "${SIGNING_ARGUMENTS[@]}" \
  --entitlements "$ENTITLEMENTS" \
  "$APP"
codesign --verify --deep --strict "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
BASE_NAME="DisplayCove-$VERSION-unsigned"

ditto \
  -c \
  -k \
  --sequesterRsrc \
  --keepParent \
  "$APP" \
  "$DIST/$BASE_NAME.zip"

mkdir -p "$STAGING"
ditto "$APP" "$STAGING/DisplayCove.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/INSTALLING-UNSIGNED.txt" <<'EOF'
DisplayCove Unsigned Release

This build is ad-hoc signed and is not notarized by Apple. macOS blocks its first
launch by default.

1. Drag DisplayCove to Applications.
2. Try to open DisplayCove once.
3. Open System Settings > Privacy & Security.
4. Choose Open Anyway for DisplayCove and confirm.
5. Grant Screen & System Audio Recording access when requested.

Install only if you trust the release downloaded from:
https://github.com/MJuma/DisplayCove/releases
EOF

diskutil image create from \
  --volumeName "DisplayCove $VERSION Unsigned" \
  --format UDZO \
  "$STAGING" \
  "$DIST/$BASE_NAME.dmg" >/dev/null

(
  cd "$DIST"
  shasum -a 256 "$BASE_NAME.zip" "$BASE_NAME.dmg" > SHA256SUMS.txt
)

echo "$DIST"
