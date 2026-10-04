#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${TMPDIR:-/tmp}/DisplayCove-Review-DerivedData"
KEYCHAIN="${DISPLAYCOVE_KEYCHAIN:?Set DISPLAYCOVE_KEYCHAIN to the signing keychain path}"
IDENTITY="${DISPLAYCOVE_SIGNING_IDENTITY:?Set DISPLAYCOVE_SIGNING_IDENTITY to the certificate name}"
APP="$DERIVED_DATA/Build/Products/Release/DisplayCove.app"
DESTINATION="$HOME/Applications/DisplayCove.app"

cd "$ROOT"
xcodebuild -quiet \
  -project DisplayCove.xcodeproj \
  -scheme DisplayCove \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  PRODUCT_BUNDLE_IDENTIFIER=dev.juma.DisplayCove \
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

codesign \
  --force \
  --sign "$IDENTITY" \
  --keychain "$KEYCHAIN" \
  --options runtime \
  --entitlements DisplayCove/DisplayCove.entitlements \
  "$APP"
codesign --verify --deep --strict "$APP"

rm -rf "$DESTINATION"
ditto "$APP" "$DESTINATION"
echo "$DESTINATION"
