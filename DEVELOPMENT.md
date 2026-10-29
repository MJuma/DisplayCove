# Developing DisplayCove

## Requirements

- macOS 27 or later.
- Xcode 27 or later selected with `xcode-select`.
- Swift 6.
- A stable local signing identity for permission-sensitive runtime testing.

The application uses private macOS virtual-display APIs. Development should be performed on a machine where unexpected display reconfiguration can be tolerated.

## Source layout

| Path | Purpose |
| --- | --- |
| `DisplayCove/AppDelegate.swift` | Application composition root |
| `DisplayCove/Coordination` | Window, menu, settings, recording, and debug coordination |
| `DisplayCove/Core` | Display lifecycle, capture, preferences, geometry, and HDR behavior |
| `DisplayCove/Recording` | ScreenCaptureKit recording implementation and UI |
| `DisplayCove/Settings` | General and Recording settings controllers |
| `DisplayCove/VirtualDisplayRuntime.*` | Runtime-validated Objective-C private API boundary |
| `Tests/DisplayCoveCoreTests` | Swift package unit tests |
| `Scripts` | Build, integration, capture, and asset-generation tools |

`AppDelegate` should remain a small composition root. Display lifecycle belongs in `DisplaySession`; application-level UI orchestration belongs in the
coordinators.

## Build and test

Run the focused validation commands from the repository root:

```bash
swift test -Xswiftc -warnings-as-errors -Xcc -Werror
bash Scripts/test-tooling.sh

xcodebuild -quiet \
  -project DisplayCove.xcodeproj \
  -scheme DisplayCove \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  build

swift run --package-path BuildTools \
  swiftformat --lint . \
  --swiftversion 6
```

The project targets Swift 6 with complete strict concurrency.

## Runtime integration

The lifecycle integration creates two virtual displays, changes a resolution, and verifies teardown:

```bash
Scripts/run-integration-tests.sh
```

The recording integration creates a HEVC recording with system audio:

```bash
Scripts/run-recording-integration.sh
```

These scripts modify the live display environment and require the relevant Screen & System Audio Recording permissions.
They build separate `dev.juma.DisplayCove.lifecycle-integration` and
`dev.juma.DisplayCove.recording-integration` apps rather than reusing the production
identity. Grant permission to these test copies separately. Production grants,
saved settings and the running production app are not reset or replaced.

Integration preferences are session-only. Recordings use a private UUID-named
temporary folder, removed after success or failure. Set
`DISPLAYCOVE_RECORDING_TEST_KEEP_OUTPUT=1` only when intentionally retaining a
test recording; its path is printed. The external runner requires both a zero
exit status and the exact success marker, enforces a 90-second application
deadline, and stops only the child it launched. Override
`DISPLAYCOVE_INTEGRATION_TIMEOUT` with an integer from 1 through 600 if needed.
Launch through these scripts, not by setting test flags on the production app.

`Scripts/test-tooling.sh` checks tag/path guards, artifact preservation, and
supervisor success/failure/timeout handling using temporary Git repositories and
a tiny fake executable. It does not create virtual displays or capture audio.

## Ownership and saved settings

A per-bundle kernel `flock` is acquired before preferences or capture coordinators
are constructed and retained for the application's lifetime. Duplicate launches
activate an existing copy and exit; PID order is not ownership evidence. Never
delete live lock files. Lock files are empty and live in the app's Application
Support directory.

Older preferences default only fields that are missing. Invalid values,
unsupported enum cases and corrupt data produce a startup warning and a banner
in the affected Settings tab. The original data remains untouched while edits
apply to the current session. Explicitly confirm **Reset saved settings** to
replace that tab's saved data with defaults.

## Release preparation

The manual release workflow checks out the exact existing version tag, runs
strict tests and lint, builds with the existing signing identity, generates the
signed Sparkle appcast, and creates or updates a **draft only**. It refuses to
replace a published release. Review and publish the draft explicitly; publishing
is what exposes its appcast to the existing latest-release feed.

Normal local packaging requires a clean checkout at the matching version tag:

```bash
DISPLAYCOVE_RELEASE_TAG=v1.0.4 bash Scripts/build-unsigned-release.sh
```

For packaging uncommitted development work only:

```bash
DISPLAYCOVE_RELEASE_TAG=v1.0.4 DISPLAYCOVE_ALLOW_DIRTY_RELEASE=1 \
  bash Scripts/build-unsigned-release.sh
```

Developer output has a `-dev` suffix and is not a release candidate. Both modes
use fresh private build/staging folders, verify ZIP/DMG/signatures/checksums,
and refuse to overwrite existing output. Normal packaging rechecks the tag,
HEAD and clean source state before publishing the local artifact directory.
Neither command changes an installed app, imports signing identities, modifies
keychain trust, creates tags or uploads files. Signing identity/keychain options
remain the same as before.

## Stable local review signing

Ad-hoc signatures cause macOS TCC grants to become stale across rebuilds. `Scripts/build-review-app.sh` builds a Release app, signs its Mach-O content with a
stable local identity, and installs it at:

```text
~/Applications/DisplayCove.app
```

Provide the development keychain and identity without editing the script:

```bash
DISPLAYCOVE_KEYCHAIN=/path/to/keychain-db \
DISPLAYCOVE_SIGNING_IDENTITY="Certificate Common Name" \
Scripts/build-review-app.sh
```

Set `DISPLAYCOVE_CONFIGURATION=Debug` when the signed build must include the integration harnesses.

The migration machine currently uses a temporary local identity, but its keychain path and certificate name are intentionally not committed. Replace it with
permanent Apple Development and Developer ID certificates before release.

Because a self-signed certificate has no Apple Team ID, the review script adds `com.apple.security.cs.disable-library-validation` only to its generated local
review entitlements so the embedded Sparkle framework can load. The checked-in production entitlements keep library validation enabled.

## Permissions

DisplayCove verifies authorization with a real ScreenCaptureKit content query. Do not replace this with `CGPreflightScreenCaptureAccess()`: it proved unreliable
for rebuilt development applications.

Changing the bundle identifier, certificate, or designated requirement can cause macOS to request permission again even when the application name is unchanged.

Switching between ad-hoc, local review, and published builds with the same bundle identifier can leave an enabled TCC entry tied to the wrong code requirement.
Reset only DisplayCove's Screen Capture record before granting the current build:

```bash
tccutil reset ScreenCapture dev.juma.DisplayCove
```

Published releases use the same signing certificate and designated requirement. A clean grant to a published build survives Sparkle updates between releases.

## Private API boundary

Private classes and selectors must remain isolated in `VirtualDisplayRuntime.h/.m`. Swift code should call only the project-owned C functions exposed through
`DisplayCove-Bridging-Header.h`.

Requirements for changes in this area:

- Resolve private classes and selectors dynamically.
- Validate every required capability before use.
- Return actionable errors rather than silently degrading.
- Preserve teardown behavior after resolution changes.
- Verify the change on the currently supported macOS release.

## Asset generation

The README hero, `Marketing/Screenshots/DisplayCove-Preview.gif`, is an
app-rendered illustration with fictional presentation and agenda windows.
Unmodified `ScreenViewController` and `ApplicationMenuController` code was
rendered against in-memory display/recording providers in an isolated target.
Only app-owned views were rasterized and composited onto original artwork.
No virtual displays were created, desktop/audio captured, permissions changed,
or production preferences accessed. This is not a live-display integration test.

Capture-only providers and rendering code are not part of the application or
shipping source. When replacing the animation, inspect every frame for private
content, clipping and readability; strip private metadata, keep the GIF below
one MiB, and verify its loop returns to the original resolution and layout.

Regenerate the icon and social preview with:

```bash
swift Scripts/generate-brand-assets.swift
```

For a separate diagnostic still image, capture a specific application window
using ScreenCaptureKit:

```bash
swift Scripts/capture-app-window.swift \
  DisplayCove \
  DisplayCove \
  Marketing/Captures/DisplayCove-Window.png
```

After capturing both virtual display windows, regenerate the multi-display composition with:

```bash
swift Scripts/compose-marketing-screenshots.swift
```

Generated artwork must remain readable at 16 × 16, contain no icon text, work in light and dark appearances, and avoid generic upload/share arrows.
