#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
mode="${1:-}"
case "$mode" in lifecycle|recording) ;; *) echo "Expected lifecycle or recording." >&2; exit 1 ;; esac
timeout="${DISPLAYCOVE_INTEGRATION_TIMEOUT:-90}"
if [[ ! "$timeout" =~ ^[1-9][0-9]*$ ]] || (( timeout > 600 )); then
  echo "DISPLAYCOVE_INTEGRATION_TIMEOUT must be 1...600 seconds." >&2
  exit 1
fi
DERIVED_DATA=$(mktemp -d "${TMPDIR:-/tmp}/DisplayCove-Integration.XXXXXX")
DERIVED_DATA=$(cd "$DERIVED_DATA" && pwd -P)
cleanup() {
  local status=$?
  trap - EXIT
  if ! swift "$ROOT/Scripts/release-files.swift" cleanup-integration-build "$DERIVED_DATA"; then
    if [[ "$status" == 0 ]]; then
      status=1
    fi
  fi
  exit "$status"
}
trap cleanup EXIT

cd "$ROOT"
identifier="dev.juma.DisplayCove.$mode-integration"
xcodebuild -quiet \
  -project DisplayCove.xcodeproj \
  -scheme DisplayCove \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- \
  PRODUCT_BUNDLE_IDENTIFIER="$identifier" \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  build
printf 'Launching isolated %s integration (timeout %ss). This changes virtual displays.\n' "$mode" "$timeout"
swift "$ROOT/Scripts/run-integration-process.swift" "$timeout" "$mode" \
  "$DERIVED_DATA/Build/Products/Debug/DisplayCove.app/Contents/MacOS/DisplayCove"
