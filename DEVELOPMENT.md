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
swift test

xcodebuild -quiet \
  -project DisplayCove.xcodeproj \
  -scheme DisplayCove \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
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

Regenerate the icon and social preview with:

```bash
swift Scripts/generate-brand-assets.swift
```

Capture a specific application window using ScreenCaptureKit:

```bash
swift Scripts/capture-app-window.swift \
  DisplayCove \
  DisplayCove \
  Marketing/Screenshots/DisplayCove-Primary.png
```

After capturing both virtual display windows, regenerate the multi-display composition with:

```bash
swift Scripts/compose-marketing-screenshots.swift
```

Generated artwork must remain readable at 16 × 16, contain no icon text, work in light and dark appearances, and avoid generic upload/share arrows.
