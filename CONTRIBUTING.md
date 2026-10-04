# Contributing to DisplayCove

DisplayCove welcomes focused bug fixes, compatibility improvements, tests, and features that support controlled virtual-display sharing.

## Before opening a pull request

1. Search existing issues.
2. Open an issue before beginning a large behavioral, architectural, private API, or user-interface change.
3. Keep changes scoped to one problem.
4. Preserve the existing user experience unless the change intentionally updates it.

## Development expectations

- Use Swift 6 and complete strict concurrency.
- Keep UI and display lifecycle work on the appropriate actor.
- Reuse existing coordinators, preferences, and geometry helpers.
- Do not expose private framework declarations directly to Swift.
- Surface failures explicitly instead of silently falling back.
- Add focused tests for new or corrected behavior.

## Validation

Before submitting:

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

Run the integration scripts when changing display creation, resolution switching, teardown, ScreenCaptureKit preview, or recording.

## Pull requests

- Target the `master` branch.
- Explain the user-visible behavior and why the chosen implementation is safe.
- Include screenshots or recordings for visible UI changes.
- Call out any private API assumptions and the macOS build used for testing.
- Do not include signing certificates, provisioning profiles, credentials, or local keychains.

By contributing, you agree that your contribution is licensed under the project's MIT License.
