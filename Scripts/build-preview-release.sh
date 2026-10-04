#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${TMPDIR:-/tmp}/DisplayCove-Preview-Release-DerivedData"
KEYCHAIN="${DISPLAYCOVE_PREVIEW_KEYCHAIN:?Set DISPLAYCOVE_PREVIEW_KEYCHAIN}"
IDENTITY="${DISPLAYCOVE_PREVIEW_SIGNING_IDENTITY:?Set DISPLAYCOVE_PREVIEW_SIGNING_IDENTITY}"
TAG="${DISPLAYCOVE_PREVIEW_TAG:-v1.0.0-preview.1}"
APP="$DERIVED_DATA/Build/Products/Release/DisplayCove.app"
ENTITLEMENTS="$DERIVED_DATA/DisplayCove-Preview.entitlements"
STAGING="$DERIVED_DATA/DisplayCove-Preview"
DIST="$ROOT/dist/$TAG"

cd "$ROOT"
rm -rf "$DERIVED_DATA" "$DIST"
mkdir -p "$DIST"

xcodebuild -quiet \
  -project DisplayCove.xcodeproj \
  -scheme DisplayCove \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

while IFS= read -r -d '' file; do
  if file "$file" | grep -q "Mach-O"; then
    codesign \
      --force \
      --sign "$IDENTITY" \
      --keychain "$KEYCHAIN" \
      --options runtime \
      "$file"
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
  --force \
  --sign "$IDENTITY" \
  --keychain "$KEYCHAIN" \
  --options runtime \
  --entitlements "$ENTITLEMENTS" \
  "$APP"
codesign --verify --deep --strict "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
BASE_NAME="DisplayCove-$VERSION-unsigned-preview"

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
cat > "$STAGING/INSTALLING-UNSIGNED-PREVIEW.txt" <<'EOF'
DisplayCove Unsigned Preview

This build is self-signed and is not notarized by Apple. macOS blocks its first
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
  --volumeName "DisplayCove $VERSION Unsigned Preview" \
  --format UDZO \
  "$STAGING" \
  "$DIST/$BASE_NAME.dmg" >/dev/null

(
  cd "$DIST"
  shasum -a 256 "$BASE_NAME.zip" "$BASE_NAME.dmg" > SHA256SUMS.txt
)

echo "$DIST"
