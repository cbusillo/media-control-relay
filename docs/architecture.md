# Architecture

## Product Boundary

Media Control Relay maps actions from local control surfaces to supported media
targets. The first target family forwards discrete Volume Up, Volume Down, and
Mute actions to a configured Samsung TV only when its activation rule matches
the current macOS audio and display state.

The app is intentionally not a universal remote, smart-home hub, media
dashboard, streaming service, or cloud relay.

## Modules

### MediaControlCore

Pure Swift logic with a Foundation-only dependency:

- relay-state precedence;
- audio/display activation matching;
- route snapshot normalization, duplicate suppression, and observer lifecycle;
- volume action semantics;
- repeat, deduplication, debounce, batch, and queue policy;
- diagnostics redaction.

This module must remain testable on public CI without AppKit, IOKit, Network,
Keychain, credentials, or TV hardware.

### MediaControlRelayApp

The native macOS shell owns:

- menu-bar, setup, and settings scenes;
- permission and local-network presentation;
- read-only Core Audio default-output and active-display observation;
- sleep/wake observer registration and volume-gesture cancellation;
- future Keychain credential storage;
- launch-at-login registration;
- coordination between input monitoring and protocol adapters.

Future control-surface and target adapters remain optional boundaries around
the local coordinator. Adding a Loupedeck, Apple TV, HomePod, or other supported
integration must not make the core app depend on that device.

The current foundation UI reports only facts that are implemented. It does not
simulate discovery, pairing, connectivity, or successful volume control.

### Route Observation

`SystemRouteObserver` reads the current default Core Audio output and active
`NSScreen` displays. Platform values are converted into normalized
`RouteSnapshot` values before they reach `RelayAppModel`. The snapshot bridges to
the existing `ActivationSnapshot`, but route observation does not change
`relayState` and does not emit target commands.

The core coalescer publishes the first snapshot immediately, suppresses
unchanged snapshots, and retains at most one pending change during its bounded
duplicate window. Sleep unregisters platform observers and cancels pending
refresh work; wake registers them again and publishes one fresh snapshot. Audio
UIDs and display identifiers remain private in memory for stable equality only.
They are not included in diagnostics or logs.

### Future Samsung Adapter

Protocol code will live behind a narrow adapter interface and enter only after
its provenance gate is complete. Legacy H/J and modern Tizen transports must be
separate implementations with explicit compatibility descriptions.

## State Resolution

State precedence is deterministic:

1. `unconfigured`
2. `unsupported`
3. `needsPermission`
4. `dormant`
5. `offline`
6. `active`

Configuration precedes permission so the app does not request global input
access before the user has a media target to configure. Dormant precedes
transport health because an inactive route should not alarm the user about an
unreachable media target.

## Activation Rule

The first activation rule matches:

- a case- and diacritic-insensitive substring of the default audio output; and
- by default, a corresponding attached display name.

No regular expressions, per-app routing, schedules, or automation rules are in
the initial scope.

## Distribution

### Developer ID

The direct build is the first release path. Release automation will add stable
Developer ID signing and notarization on top of the hardened-runtime build so
Input Monitoring approval survives updates. The foundation has no self-updater.

### Mac App Store

The App Store configuration enables App Sandbox and outbound network access.
It remains experimental until a signed sandbox probe proves that the passive
media-key path works with Input Monitoring on supported macOS versions.

The App Store app must remain useful without third-party integrations and must
not write into another application's support directory.

## Explicit Exclusions

- private configuration files or credentials;
- host-specific installers and LaunchAgents;
- the prototype Go helper process;
- pairing implementations with unresolved provenance;
- automatic Loupedeck installation or profile mutation;
- telemetry, accounts, or remote network relays.
