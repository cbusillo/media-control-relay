# Architecture

## Product Boundary

Media Control Relay maps actions from local control surfaces to supported media
targets. Milestone 0.1 proves the routing boundary with an explicitly labeled
in-process preview target. The preview records eligible Volume Up, Volume Down,
and Mute actions but does not connect to or control a TV or other media device.

The app is intentionally not a universal remote, smart-home hub, media
dashboard, streaming service, or cloud relay.

## Modules

### MediaControlCore

Pure Swift logic with a Foundation-only dependency:

- transport-neutral media-target identity, absolute-volume operations, and
  reconciliation contracts;
- relay-state precedence;
- audio/display activation matching;
- Codable local target configuration and route-derived preview setup;
- route snapshot normalization, duplicate suppression, and observer lifecycle;
- volume action semantics;
- repeat, deduplication, debounce, batch, and queue policy;
- deterministic routing reduction and bounded preview command recording;
- deterministic absolute-volume planning, optional bounded reread input, and
  transport-neutral failure taxonomy;
- target-aware status copy;
- diagnostics redaction.

This module must remain testable on public CI without AppKit, IOKit, Network,
URLSession, URL, SOAP, XML, SSDP, Keychain, credentials, or TV hardware.

### MediaControlRelayApp

The native macOS shell owns:

- menu-bar, setup, and settings scenes;
- permission presentation;
- read-only Core Audio default-output and active-display observation;
- sleep/wake observer registration and volume-gesture cancellation;
- local preview configuration in UserDefaults; the preview has no secrets;
- the thin main-actor coordinator that applies reducer outputs;
- launch-at-login registration;
- future coordination between input monitoring and protocol adapters.

Future control-surface and target adapters remain optional boundaries around
the local coordinator. Adding a Loupedeck, Apple TV, HomePod, or other supported
integration must not make the core app depend on that device.

The current foundation UI reports only facts that are implemented. It records
preview commands locally, clearly identifies the sink as a preview, and states
that no media device is connected or controlled and normal Mac volume behavior
is preserved. It does not simulate discovery, pairing, network connectivity, or
hardware control.

The asynchronous `MediaVolumeTarget` contract reads current volume/mute state
and applies exactly one absolute-volume or mute operation. Apply returns the
confirmed state, so transport success alone is not command success. Read-back
must match the requested dimension; unrelated volume or mute changes may reflect
a physical remote or another controller and remain valid refreshed state. The
pure reconciler maps relative actions onto clamped operations, emits an explicit
no-change result at a rail, and can use one caller-supplied refreshed state when
a cache is stale or a prior read-back mismatched. Held repeats remain bounded by
`VolumeCommandQueuePolicy`; adjacent same-direction steps may be coalesced only
up to its batch limit, while discrete action order and mute toggles are
preserved. The reconciler plans state changes but does not own a second queue.

Stable media-target identity stays in core while addresses, control URLs,
friendly names, and other ephemeral locator data remain private to adapters.

### UPnPMediaTarget

The separate UPnP transport module is intentionally narrow and outbound-only:

- HTTP-only endpoint validation for local IPv4 literals;
- bounded device-description parsing with DTD/entity rejection;
- stable UDN extraction and exact RenderingControl control-URL resolution.

Both the SSDP `LOCATION` used to fetch a description and any declared
`URLBase` must pass endpoint validation. A safe base never legitimizes an unsafe
description location, and a present but malformed base fails closed.

The module does not open sockets, issue SOAP requests, touch AppKit, or talk
to real devices in the first slice. Endpoint and descriptor safety stay in this
module so the core contract remains transport-neutral.

### Route Observation

`SystemRouteObserver` reads the current default Core Audio output and active
`NSScreen` displays. Platform values are converted into normalized
`RouteSnapshot` values before they reach `RelayAppModel`. The snapshot bridges to
the existing `ActivationSnapshot`. The `RelayRoutingReducer` invalidates cached
matching whenever observation is not `observing`, so suspended or stopped
observation cannot continue recording. The app coordinator sends eligible
reducer commands to the in-process preview sink only.

The core coalescer publishes the first snapshot immediately, suppresses
unchanged snapshots, and retains at most one pending change during its bounded
duplicate window. Sleep unregisters platform observers and cancels pending
refresh work; wake registers them again and publishes one fresh snapshot. Audio
UIDs and display identifiers remain private in memory for stable equality only.
They are not included in diagnostics or logs.

### Future Samsung Adapter

Protocol code will live behind a narrow adapter interface and enter only after
its provenance gate is complete. Legacy H/J and modern Tizen transports must be
separate implementations with explicit compatibility descriptions. The current
pure-core media-target contract is original Swift code and does not import or
require Samsung framing, SOAP, XML, SSDP, URLSession, or other transport
implementations. Transport-specific faults map onto the neutral core failure
taxonomy instead of leaking protocol vocabulary into routing or UI state.

The first UPnP adapter is outbound-only and limited to RenderingControl volume
and mute. It has no GENA listener, pairing flow, credential storage, encrypted
fallback, power action, or general device-browser surface. Discovery may retain
stable identity, but addresses and control URLs are ephemeral and must be
re-resolved after interface or endpoint changes.

Adapter requests must use validated local HTTP endpoints discovered from the
matched target, reject redirects and unsafe schemes or hosts, cap response
sizes, and fail closed on malformed XML. XML parsing must reject DTDs and
external entities. A transport write is successful only after matching state
read-back; permission, discovery, offline, capability, timeout, malformed
response, protocol-fault, read-back-mismatch, and cancellation outcomes map to
the transport-neutral core failure taxonomy.

## State Resolution

State precedence is deterministic:

1. `unconfigured`
2. `unsupported`
3. `needsPermission`
4. `dormant`
5. `checkingTarget`
6. `offline`
7. `active`

Configuration precedes permission so the app does not request global input
access before the user has a media target to configure. Dormant precedes
transport health because an inactive route should not alarm the user about an
unreachable media target. Unknown reachability is `checkingTarget`, never
`offline`; offline requires an explicit unreachable observation.

## Activation Rule

The first activation rule matches:

- a case- and diacritic-insensitive substring of the default audio output; and
- for display transports, a corresponding attached display name when its name
  is related to the audio output; otherwise audio-only matching is used.

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
