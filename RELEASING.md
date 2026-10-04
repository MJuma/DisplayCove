# Releasing DisplayCove

DisplayCove publishes stable releases only. Public artifacts must be signed
with Developer ID, notarized, stapled, and distributed through GitHub Releases
and the `displaycove` Homebrew cask.

## Versioning

- Marketing version: semantic versions beginning with `1.0.0`.
- Build version: monotonically increasing CI/release counter.
- Git tag: `v<marketing-version>`, for example `v1.0.0`.
- Default branch: `master`.

## Prerequisites

- The permanent Apple Developer Team ID is configured.
- Apple Development is used for local development.
- Developer ID Application is used for public distribution.
- Notary credentials are available to CI through protected secrets.
- Sparkle update signing keys are available to the release workflow.
- The release notes and Homebrew cask have been prepared.

Never store certificates, private keys, notary credentials, or Sparkle private
keys in the repository.

## Release validation

Before creating a tag:

```bash
swift test

xcodebuild -quiet \
  -project DisplayCove.xcodeproj \
  -scheme DisplayCove \
  -configuration Release \
  CODE_SIGNING_ALLOWED=NO \
  build

swift run --package-path BuildTools \
  swiftformat --lint . \
  --swiftversion 6

Scripts/run-integration-tests.sh
Scripts/run-recording-integration.sh
```

Also verify:

- First-launch permission guidance.
- Preview and pointer interaction.
- Resolution switching and HiDPI selection.
- Multiple independent virtual displays.
- Closing displays and quitting removes every virtual display.
- Physical HDR restoration.
- H.264 and HEVC recording.
- System and microphone audio.
- Sparkle feed and signature validation.
- The installed application reports the intended bundle, version, and build.

## Archive and sign

Archive with the Release configuration and permanent team:

```bash
xcodebuild archive \
  -project DisplayCove.xcodeproj \
  -scheme DisplayCove \
  -configuration Release \
  -archivePath build/DisplayCove.xcarchive
```

Export a Developer ID application using the release export options maintained
by the release workflow. Verify the result:

```bash
codesign --verify --deep --strict --verbose=2 DisplayCove.app
spctl --assess --type execute --verbose=2 DisplayCove.app
```

## Notarize

Package the application as the approved disk image, submit it with
`xcrun notarytool`, wait for acceptance, and staple the ticket:

```bash
xcrun notarytool submit DisplayCove.dmg \
  --keychain-profile DISPLAYCOVE_NOTARY \
  --wait

xcrun stapler staple DisplayCove.dmg
xcrun stapler validate DisplayCove.dmg
```

## Publish

1. Create and push the signed `v<version>` tag.
2. Publish the notarized disk image and checksums in a GitHub Release.
3. Publish the signed Sparkle appcast entry.
4. Update the Homebrew cask URL, version, and SHA-256.
5. Install from both GitHub and Homebrew on a clean account.
6. Confirm Screen Recording onboarding and update discovery.

## After release

- Monitor GitHub Issues for launch, permission, and virtual-display teardown
  failures.
- Do not remove the temporary development signing identity until the permanent
  development and release paths have both passed final validation.
