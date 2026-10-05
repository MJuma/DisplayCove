#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${TMPDIR:-/tmp}/DisplayCove-Review-DerivedData"
KEYCHAIN="${DISPLAYCOVE_KEYCHAIN:?Set DISPLAYCOVE_KEYCHAIN to the signing keychain path}"
IDENTITY="${DISPLAYCOVE_SIGNING_IDENTITY:?Set DISPLAYCOVE_SIGNING_IDENTITY to the certificate name}"
CONFIGURATION="${DISPLAYCOVE_CONFIGURATION:-Release}"
APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/DisplayCove.app"
DESTINATION="$HOME/Applications/DisplayCove.app"
REVIEW_ENTITLEMENTS="$DERIVED_DATA/DisplayCove-Review.entitlements"

cd "$ROOT"
rm -rf "$DERIVED_DATA"
xcodebuild -quiet \
  -project DisplayCove.xcodeproj \
  -scheme DisplayCove \
  -configuration "$CONFIGURATION" \
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

cp DisplayCove/DisplayCove.entitlements "$REVIEW_ENTITLEMENTS"
/usr/libexec/PlistBuddy \
  -c "Set :com.apple.security.temporary-exception.mach-lookup.global-name:1 dev.juma.DisplayCove-spks" \
  -c "Set :com.apple.security.temporary-exception.mach-lookup.global-name:2 dev.juma.DisplayCove-spki" \
  "$REVIEW_ENTITLEMENTS"
/usr/libexec/PlistBuddy \
  -c "Add :com.apple.security.cs.disable-library-validation bool true" \
  "$REVIEW_ENTITLEMENTS"

codesign \
  --force \
  --sign "$IDENTITY" \
  --keychain "$KEYCHAIN" \
  --options runtime \
  --entitlements "$REVIEW_ENTITLEMENTS" \
  "$APP"
codesign --verify --deep --strict "$APP"

rm -rf "$DESTINATION"
ditto "$APP" "$DESTINATION"
echo "$DESTINATION"
