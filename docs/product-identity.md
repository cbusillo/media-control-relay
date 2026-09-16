# Product Identity

Decision date: August 25, 2026.
Menu-bar identity updated: September 16, 2026.

## Product Name

The durable product name is **Media Control Relay**.

Media Control Relay is a quiet native macOS menu-bar utility for routing local
keyboard volume and mute actions to a selected supported media target. The
current product surface is intentionally focused on target selection, permission
recovery, route-aware status, and reliable volume control.

The menu bar uses a stable monochrome relay glyph so its identity remains clear
as status changes. The popover keeps the current status and confirmed target
readout glanceable, shows setup access only when configuration or permission
recovery needs it, and leaves detailed setup and recovery controls in Settings.
This product remains a focused volume relay rather than a universal remote,
smart-home hub, streaming service, or cloud relay.

## Repository And Code

- GitHub repository and local checkout: `media-control-relay`
- Xcode project, app target, and Swift package: `MediaControlRelay`
- Application source module: `MediaControlRelayApp`
- Pure Swift domain module: `MediaControlCore`
- Core test target: `MediaControlCoreTests`
- SwiftUI entry point: `RelayApp`
- Application model and state: `RelayAppModel` and `RelayState`

Volume-specific domain types such as `VolumeAction`, `VolumeKeyEvent`, and
`VolumeKeyGestureTracker` retain their precise names. Target- or surface-specific
implementations must remain behind adapters.

## Bundle Namespace

- Production root: `com.shinycomputers.media-control-relay`
- Local sandbox probe: `com.shinycomputers.media-control-relay.sandbox-probe`
- Core tests: `com.shinycomputers.media-control-relay.core-tests`

Future helpers or extensions must use a purpose-specific suffix under the same
root rather than inventing a separate product namespace.

## Compatibility Language

Vendor and device names describe compatibility, not product ownership or
affiliation. Public copy may say “for compatible Samsung TVs” or name another
validated target without placing that vendor in the product name.

## Migration Boundary

The previous development identity used `TV Volume Bridge`, repository
`tv-volume-bridge-for-samsung`, and bundle root
`com.shinycomputers.tv-volume-bridge`. No public release, production App Store
record, durable Keychain credential, or implemented login item used that
identity. The old development app, preferences, sandbox container, and Input
Monitoring records were retired after the renamed signed builds passed the
runtime matrix documented in [the Input Monitoring probe](input-monitoring.md).

The separate working `Samsung TV Volume` prototype is not part of this rename.
It remains installed until Media Control Relay reaches the cutover finish line
tracked in issue #8.
