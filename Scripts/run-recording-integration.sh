#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${TMPDIR:-/tmp}/DisplayCove-Recording-DerivedData"
OUTPUT_FILE="$HOME/Library/Containers/dev.juma.DisplayCove/Data/tmp/recording.mov"

mkdir -p "$(dirname "$OUTPUT_FILE")"

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
  DISPLAYCOVE_RECORDING_TEST_OUTPUT="$OUTPUT_FILE" \
  DISPLAYCOVE_RECORDING_TEST_DURATION=1 \
  DISPLAYCOVE_RECORDING_TEST_CODEC=hevc \
  DISPLAYCOVE_RECORDING_TEST_FRAME_RATE=60 \
  DISPLAYCOVE_RECORDING_TEST_QUALITY=compact \
  DISPLAYCOVE_RECORDING_TEST_SYSTEM_AUDIO=1 \
    "$DERIVED_DATA/Build/Products/Debug/DisplayCove.app/Contents/MacOS/DisplayCove" \
    2>&1
)"
printf '%s\n' "$OUTPUT"
grep -q "DISPLAYCOVE_RECORDING_INTEGRATION_SUCCESS" <<<"$OUTPUT"
