#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
suite=$(mktemp -d "${TMPDIR:-/tmp}/DisplayCove-Tooling.XXXXXX")
suite=$(cd "$suite" && pwd -P)
cleanup() {
  local status=$?
  trap - EXIT
  if ! swift - "$suite" <<'SWIFT'
import Foundation
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard url.lastPathComponent.hasPrefix("DisplayCove-Tooling.") else { fatalError("Unexpected test fixture") }
try FileManager.default.removeItem(at: url)
SWIFT
  then
    if [[ "$status" == 0 ]]; then
      status=1
    fi
  fi
  exit "$status"
}
trap cleanup EXIT
fixture="$suite/repo"
mkdir -p "$fixture/Scripts" "$fixture/bin" "$suite/temp" "$suite/runtime" "$suite/protected"
printf 'preserved\n' > "$suite/protected/marker"
cp "$ROOT/Scripts/build-unsigned-release.sh" "$ROOT/Scripts/release-files.swift" "$fixture/Scripts/"
printf 'dist/\n' > "$fixture/.gitignore"
cat > "$fixture/bin/xcodebuild" <<'BUILD'
#!/bin/bash
set -euo pipefail
case "$DISPLAYCOVE_FAKE_BUILD" in
  probe) echo BUILD_REACHED; exit 73 ;;
  delete-tag) git update-ref -d refs/tags/v1.0.0 ;;
  move-tag) git update-ref refs/tags/v1.0.0 "$(git rev-parse HEAD^)" ;;
  move-head) git update-ref HEAD "$(git rev-parse HEAD^)" ;;
  *) exit 74 ;;
esac
BUILD
chmod +x "$fixture/bin/xcodebuild"
git_fixture() {
  git -C "$fixture" -c user.name='Tooling Tests' -c user.email='tests@example.invalid' \
    -c commit.gpgsign=false -c tag.gpgsign=false -c core.hooksPath=/dev/null "$@"
}
git_fixture init --quiet --initial-branch main
git_fixture add --force .
git_fixture commit --quiet -m 'Initial fixture'
git_fixture commit --quiet --allow-empty -m 'Second fixture'

expect_release() {
  local name="$1" tag="$2" mode="$3" expected="$4" message="$5" status=0 output
  output=$(PATH="$fixture/bin:$PATH" TMPDIR="$suite/temp/" GITHUB_OUTPUT= \
    DISPLAYCOVE_RELEASE_TAG="$tag" DISPLAYCOVE_FAKE_BUILD="$mode" \
    DISPLAYCOVE_ALLOW_DIRTY_RELEASE=0 DISPLAYCOVE_KEEP_RELEASE_WORKSPACE=0 \
    bash "$fixture/Scripts/build-unsigned-release.sh" 2>&1) || status=$?
  if [[ "$status" != "$expected" ]] || ! grep -Fq "$message" <<< "$output"; then
    printf 'FAILED: %s (%s)\n%s\n' "$name" "$status" "$output" >&2
    exit 1
  fi
  if [[ -n "$(find "$suite/temp" -mindepth 1 -maxdepth 1 -name 'DisplayCove-Release.*' -print -quit)" ]]; then
    echo "Release test leaked a workspace." >&2
    exit 1
  fi
  printf 'Passed: %s\n' "$name"
}
expect_release 'unsafe tag rejected before filesystem changes' '../protected' probe 1 'Set DISPLAYCOVE_RELEASE_TAG'
test "$(cat "$suite/protected/marker")" = preserved
printf 'uncommitted\n' > "$fixture/uncommitted"
expect_release 'dirty source rejected' v1.0.0 probe 1 'Refusing to release dirty sources'
rm "$fixture/uncommitted"
expect_release 'missing tag rejected' v1.0.0 probe 1 'Release tag does not exist'
git_fixture branch v1.0.0
expect_release 'branch-only version rejected' v1.0.0 probe 1 'Release tag does not exist'
git_fixture tag v1.0.0
expect_release 'lightweight version tag accepted' v1.0.0 probe 73 BUILD_REACHED
git_fixture tag --delete v1.0.0 >/dev/null
git_fixture tag --annotate v1.0.0 -m 'Annotated fixture'
expect_release 'annotated version tag accepted' v1.0.0 probe 73 BUILD_REACHED
git_fixture tag --delete v1.0.0 >/dev/null
git_fixture tag v1.0.0 HEAD^
expect_release 'wrong tag target rejected' v1.0.0 probe 1 'Release tag does not point'
git_fixture tag --delete v1.0.0 >/dev/null
git_fixture tag v1.0.0
expect_release 'tag deletion during build rejected' v1.0.0 delete-tag 1 'Source checkout or release tag changed'
git_fixture tag v1.0.0
expect_release 'tag movement during build rejected' v1.0.0 move-tag 1 'Source checkout or release tag changed'
git_fixture tag --delete v1.0.0 >/dev/null
git_fixture tag v1.0.0
expect_release 'HEAD movement during build rejected' v1.0.0 move-head 1 'Source checkout or release tag changed'

mkdir -p "$fixture/dist/v1.0.0-dev" "$fixture/dist/.displaycove-release.fixture"
printf 'original\n' > "$fixture/dist/v1.0.0-dev/marker"
printf 'candidate\n' > "$fixture/dist/.displaycove-release.fixture/marker"
status=0
output=$(DISPLAYCOVE_RELEASE_TAG=v1.0.0 DISPLAYCOVE_ALLOW_DIRTY_RELEASE=1 \
  DISPLAYCOVE_KEEP_RELEASE_WORKSPACE=0 bash "$fixture/Scripts/build-unsigned-release.sh" 2>&1) || status=$?
if [[ "$status" != 1 ]] || ! grep -Fq 'will not be overwritten' <<< "$output"; then
  printf 'Existing-output guard failed:\n%s\n' "$output" >&2; exit 1
fi
if swift "$fixture/Scripts/release-files.swift" publish \
  "$fixture/dist/.displaycove-release.fixture" "$fixture/dist/v1.0.0-dev" >/dev/null 2>&1; then
  echo 'Existing release artifacts were overwritten.' >&2; exit 1
fi
test "$(cat "$fixture/dist/v1.0.0-dev/marker")" = original
test "$(cat "$fixture/dist/.displaycove-release.fixture/marker")" = candidate
swift "$fixture/Scripts/release-files.swift" publish \
  "$fixture/dist/.displaycove-release.fixture" "$fixture/dist/v2.0.0-dev"
test "$(cat "$fixture/dist/v2.0.0-dev/marker")" = candidate
ln -s "$suite/protected" "$fixture/dist/.displaycove-release.link"
if swift "$fixture/Scripts/release-files.swift" cleanup-stage \
  "$fixture/dist/.displaycove-release.link" >/dev/null 2>&1; then
  echo 'A symlink staging directory was accepted.' >&2; exit 1
fi
test "$(cat "$suite/protected/marker")" = preserved
printf 'Passed: artifact preservation, atomic publication and symlink rejection\n'

app="$suite/Fake.app"
mkdir -p "$app/Contents/MacOS"
cat > "$suite/process.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <sys/stat.h>
#include <unistd.h>
int main(void) {
    char path[4096];
    snprintf(path, sizeof(path), "%s/displaycove-integration-%s",
        getenv("DISPLAYCOVE_FAKE_ROOT"), getenv("DISPLAYCOVE_INTEGRATION_RUN_ID"));
    if (mkdir(path, 0700) != 0) return 2;
    printf("DISPLAYCOVE_INTEGRATION_DIRECTORY=%s\n", path);
    fflush(stdout);
    const char *mode = getenv("DISPLAYCOVE_FAKE_PROCESS");
    if (strcmp(mode, "timeout") == 0) {
        signal(SIGTERM, SIG_IGN);
        sleep(30);
    }
    if (strcmp(mode, "missing") == 0) return 0;
    puts(getenv("DISPLAYCOVE_LIFECYCLE_TEST") ?
        "DISPLAYCOVE_LIFECYCLE_INTEGRATION_SUCCESS" :
        "DISPLAYCOVE_RECORDING_INTEGRATION_SUCCESS");
    return strcmp(mode, "failed") == 0 ? 1 : 0;
}
C
clang -Wall -Wextra -Werror "$suite/process.c" -o "$app/Contents/MacOS/Fake"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string dev.juma.DisplayCove.lifecycle-integration' \
  "$app/Contents/Info.plist" >/dev/null
expect_runner() {
  local name="$1" mode="$2" succeeds="$3" status=0 output
  output=$(DISPLAYCOVE_FAKE_PROCESS="$mode" DISPLAYCOVE_FAKE_ROOT="$suite/runtime" \
    swift "$ROOT/Scripts/run-integration-process.swift" 0.3 lifecycle "$app/Contents/MacOS/Fake" 2>&1) || status=$?
  if { [[ "$succeeds" == yes && "$status" != 0 ]]; } ||
     { [[ "$succeeds" == no && "$status" == 0 ]]; }; then
    printf 'FAILED: %s\n%s\n' "$name" "$output" >&2; exit 1
  fi
  test -z "$(find "$suite/runtime" -mindepth 1 -maxdepth 1 -print -quit)"
  printf 'Passed: %s\n' "$name"
}
expect_runner 'isolated successful process accepted' success yes
expect_runner 'nonzero process rejected despite success marker' failed no
expect_runner 'missing success marker rejected' missing no
expect_runner 'hung process killed within deadline' timeout no
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.juma.DisplayCove' "$app/Contents/Info.plist"
expect_runner 'production bundle refused before launch' success no
printf 'All tooling checks passed without creating virtual displays or recording audio.\n'
