# DisplayCove Privacy

DisplayCove is designed to process screen and audio content locally on the Mac.
It does not include analytics, advertising, user tracking, or usage telemetry.

## Screen and audio capture

DisplayCove requests **Screen & System Audio Recording** access to:

- Show the virtual display inside the DisplayCove window.
- Record the selected virtual display.
- Include system audio when that option is enabled.

ScreenCaptureKit supplies these frames directly to the local preview and
recording pipeline. DisplayCove does not upload captured frames or audio.

## Microphone

Microphone access is requested only when microphone recording is enabled. The
selected microphone is recorded into the user-selected movie file and is not
transmitted by DisplayCove.

## Files

DisplayCove writes a recording only after the user selects a destination in the
macOS save panel. The app sandbox grants access to that selected location.

## Preferences

General and Recording preferences are stored locally in the standard macOS
preferences domain for `dev.juma.DisplayCove`. DisplayCove intentionally does
not import or delete DeskPad preferences.

Removing the application does not automatically remove its macOS preferences
or permissions. Those can be removed through System Settings or the standard
macOS preference-management tools.

## Updates

DisplayCove 1.0 is intended to use Sparkle for signed update checks. An update
check contacts the official DisplayCove update feed and necessarily exposes
standard network metadata such as the device's IP address and app version to
the hosting provider. DisplayCove does not attach analytics or screen content
to update requests.

Users installing through Homebrew can instead update with Homebrew.

## Private APIs

DisplayCove uses private macOS APIs to create virtual displays and optionally
restore physical-display HDR state. These calls operate locally and do not
send information to the developer.

## Questions

Open a privacy issue at
<https://github.com/MJuma/DisplayCove/issues> without attaching private screen
recordings, credentials, or other sensitive content.
