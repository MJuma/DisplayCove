#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${TMPDIR:-/tmp}/DisplayCove-Integration-DerivedData"

cd "$ROOT"
xcodebuild -quiet \
  -project DisplayCove.xcodeproj \
  -scheme DisplayCove \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  CODE_SIGN_IDENTITY=- \
  PRODUCT_BUNDLE_IDENTIFIER=dev.juma.DisplayCove \
  build

OUTPUT="$(
  DISPLAYCOVE_LIFECYCLE_TEST=1 \
    "$DERIVED_DATA/Build/Products/Debug/DisplayCove.app/Contents/MacOS/DisplayCove" \
    2>&1
)"
printf '%s\n' "$OUTPUT"
grep -q "DISPLAYCOVE_LIFECYCLE_INTEGRATION_SUCCESS" <<<"$OUTPUT"
