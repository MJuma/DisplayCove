#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
KEYCHAIN="${DISPLAYCOVE_SIGNING_KEYCHAIN:-}"
IDENTITY="${DISPLAYCOVE_SIGNING_IDENTITY:--}"
TAG="${DISPLAYCOVE_RELEASE_TAG:-}"
DEVELOPER_BUILD="${DISPLAYCOVE_ALLOW_DIRTY_RELEASE:-0}"
KEEP_WORKSPACE="${DISPLAYCOVE_KEEP_RELEASE_WORKSPACE:-0}"

cd "$ROOT"
if [[ ! "$TAG" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "Set DISPLAYCOVE_RELEASE_TAG to a version tag, such as v1.0.4." >&2
  exit 1
fi
case "$DEVELOPER_BUILD" in 0|1) ;; *) echo "Invalid DISPLAYCOVE_ALLOW_DIRTY_RELEASE" >&2; exit 1 ;; esac
case "$KEEP_WORKSPACE" in 0|1) ;; *) echo "Invalid DISPLAYCOVE_KEEP_RELEASE_WORKSPACE" >&2; exit 1 ;; esac
if [[ "$KEEP_WORKSPACE" == 1 && -z "${GITHUB_OUTPUT:-}" ]]; then
  echo "Retained release workspaces require a GitHub step output file." >&2
  exit 1
fi
suffix=""
if [[ "$DEVELOPER_BUILD" == 1 ]]; then
  suffix="-dev"
  echo "Preparing developer artifacts, not a publishable release." >&2
else
  GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || GIT_ROOT=""
  if [[ "$GIT_ROOT" != "$ROOT" ]] || ! git rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "Release preparation requires its own Git checkout." >&2
    exit 1
  fi
  if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    echo "Refusing to release dirty sources." >&2
    exit 1
  fi
  if ! TAG_COMMIT=$(git rev-parse --verify "refs/tags/$TAG^{commit}" 2>/dev/null); then
    echo "Release tag does not exist: $TAG" >&2
    exit 1
  fi
  if [[ "$TAG_COMMIT" != "$(git rev-parse HEAD)" ]]; then
    echo "Release tag does not point to this checkout." >&2
    exit 1
  fi
fi
DIST="$ROOT/dist/$TAG$suffix"
if [[ -L "$ROOT/dist" ]]; then
  echo "Refusing a symbolic-link artifact directory." >&2
  exit 1
fi
if [[ -e "$DIST" || -L "$DIST" ]]; then
  echo "Artifact destination already exists and will not be overwritten: $DIST" >&2
  exit 1
fi
WORK=$(mktemp -d "${TMPDIR:-/tmp}/DisplayCove-Release.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
stage=""
cleanup() {
  local status=$?
  trap - EXIT
  if [[ -n "$stage" ]]; then
    swift "$ROOT/Scripts/release-files.swift" cleanup-stage "$stage" || status=1
  fi
  if [[ "$KEEP_WORKSPACE" != 1 ]]; then
    swift "$ROOT/Scripts/release-files.swift" cleanup-workspace "$WORK" || status=1
  fi
  exit "$status"
}
trap cleanup EXIT
DERIVED_DATA="$WORK/DerivedData"
APP="$DERIVED_DATA/Build/Products/Release/DisplayCove.app"
ENTITLEMENTS="$WORK/DisplayCove-Unsigned.entitlements"
STAGING="$WORK/DisplayCove-Unsigned"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'workspace=%s\napp_path=%s\n' "$WORK" "$APP" >> "$GITHUB_OUTPUT"
fi

SIGNING_ARGUMENTS=(
  --force
  --sign "$IDENTITY"
  --options runtime
)
if [[ -n "$KEYCHAIN" ]]; then
  SIGNING_ARGUMENTS+=(--keychain "$KEYCHAIN")
fi

verify_source() {
  if [[ "$DEVELOPER_BUILD" == 0 ]] && {
    [[ -n "$(git status --porcelain --untracked-files=normal)" ]] ||
    [[ "$(git rev-parse HEAD)" != "$TAG_COMMIT" ]] ||
    [[ "$(git rev-parse --verify "refs/tags/$TAG^{commit}" 2>/dev/null)" != "$TAG_COMMIT" ]]
  }; then
    echo "Source checkout or release tag changed during packaging." >&2
    exit 1
  fi
}

xcodebuild -quiet \
  -project DisplayCove.xcodeproj \
  -scheme DisplayCove \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  build

verify_source
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
if [[ "$TAG" != "v$VERSION" ]]; then
  echo "Release tag does not match app version $VERSION." >&2
  exit 1
fi

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

BASE_NAME="DisplayCove-$VERSION-unsigned$suffix"
mkdir -p "$ROOT/dist"
stage=$(mktemp -d "$ROOT/dist/.displaycove-release.XXXXXX")

ditto \
  -c \
  -k \
  --sequesterRsrc \
  --keepParent \
  "$APP" \
  "$stage/$BASE_NAME.zip"

mkdir -p "$STAGING"
ditto "$APP" "$STAGING/DisplayCove.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/INSTALLING-UNSIGNED.txt" <<'EOF'
DisplayCove Unsigned Release

This build is self-signed and is not notarized by Apple. macOS 27 may offer
only Move to Trash or Done instead of a usable Open Anyway confirmation.

1. Drag DisplayCove to Applications.
2. Open Terminal and run:
   xattr -dr com.apple.quarantine /Applications/DisplayCove.app
3. Open DisplayCove:
   open /Applications/DisplayCove.app
4. Grant Screen & System Audio Recording access when requested.

Install only if you trust the release downloaded from:
https://github.com/MJuma/DisplayCove/releases
EOF

diskutil image create from \
  --volumeName "DisplayCove $VERSION Unsigned" \
  --format UDZO \
  "$STAGING" \
  "$stage/$BASE_NAME.dmg" >/dev/null

hdiutil verify "$stage/$BASE_NAME.dmg"
ditto -x -k "$stage/$BASE_NAME.zip" "$WORK/verify"
codesign --verify --deep --strict "$WORK/verify/DisplayCove.app"
cmp "$APP/Contents/MacOS/DisplayCove" "$WORK/verify/DisplayCove.app/Contents/MacOS/DisplayCove"

(
  cd "$stage"
  shasum -a 256 "$BASE_NAME.zip" "$BASE_NAME.dmg" > SHA256SUMS.txt
  shasum -a 256 -c SHA256SUMS.txt
)

verify_source
swift "$ROOT/Scripts/release-files.swift" publish "$stage" "$DIST"
stage=""
echo "$DIST"
