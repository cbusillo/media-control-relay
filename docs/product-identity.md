# Product Identity

Decision date: August 24, 2026.

## Product Name

The durable product name is **Media Control Relay**.

Media Control Relay routes actions from local control surfaces to supported
media targets. Compatible Samsung TVs are the first target family. Optional
integrations may add Apple TV, HomePod, Loupedeck, and other control surfaces or
media targets without turning the product into a universal remote, smart-home
hub, streaming service, or cloud relay.

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
