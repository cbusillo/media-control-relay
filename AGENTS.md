# Media Control Relay Agent Notes

## Product Shape

Media Control Relay is a focused native macOS menu-bar app that routes actions
from local control surfaces to supported media devices. Compatible Samsung TVs
are the first target family; the product is not a universal remote or a
general-purpose smart-home hub.

## Engineering Defaults

- Prefer Swift 6, SwiftUI, Swift Package Manager, and XcodeGen.
- Keep `MediaControlCore` pure and testable without AppKit, IOKit, Network, or
  real TV hardware.
- Keep control surfaces and media-target protocol families behind adapters. Do
  not let Samsung-, Apple-, or device-specific framing leak into routing or UI
  state.
- Use Keychain for credentials. Never log or commit hosts, session keys,
  session IDs, device UUIDs, tokens, or raw pairing responses.
- Model dormant, permission, unsupported, offline, and unconfigured states
  explicitly. Dormant is normal, not an error.
- Do not add pairing source, firmware-derived keys, or protocol code until the
  provenance audit explicitly permits it.
- Keep the App Store app useful without Loupedeck or any other third-party
  integration.

## UI Direction

- Use native macOS controls and system colors.
- Keep the menu short and glanceable.
- Use setup and settings windows for explanation and recovery.
- Do not show a working or connected state that the implementation has not
  actually established.
- Accessibility, keyboard navigation, light/dark mode, reduced motion, and
  increased contrast are first-release requirements.

## Validation

Run `scripts/check.sh` before review. Real-device tests are opt-in and must never
be required for public CI.
