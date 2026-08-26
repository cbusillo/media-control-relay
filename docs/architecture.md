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
Relay configuration can represent a generic UPnP MediaRenderer using only that
stable identity and a non-identifying display label. Local-network denial is a
distinct relay state from Input Monitoring denial, and the reducer still
requires a fresh matching route plus reachable transport before emitting target
work. `MediaTargetCommandExecutor` turns one routed relative action into one
current-state read and at most one absolute target write without owning another
queue or transport cache.

### UPnPMediaTarget

The separate UPnP transport module is intentionally narrow and outbound-only:

- HTTP-only endpoint validation for local IPv4 literals;
- bounded device-description parsing with DTD/entity rejection;
- stable UDN extraction and exact RenderingControl control-URL resolution;
- exact RenderingControl:1 SOAP request/response coding for Volume and Mute;
- ephemeral, credential-free URLSession requests with redirect rejection,
  bounded timeouts, cancellation, one connection per host, and streamed
  response-size enforcement.

The discovery slice adds a strict, case-insensitive SSDP response parser that
retains only validated `LOCATION`, `USN`, and derived stable identity values;
an injectable search protocol; and a macOS-supported IPv4 UDP M-SEARCH
implementation bounded by response size, candidate count, cancellation, and
elapsed time. A descriptor fetcher uses the existing bounded HTTP transport,
requires HTTP 200, and rejects any response URL that is not exactly the
requested `LOCATION`. The resolver actor caches one descriptor per discovery
generation, skips duplicate or mismatched candidates, and discards the cache on
interface or lifecycle invalidation before searching again by stable identity.

The target-execution actor conforms to the transport-neutral
`MediaVolumeTarget` contract and explicitly serializes operations across async
transport calls. Reads combine generic `ui2` volume and mute state. Writes send
one absolute Volume or Mute operation and return only after full state read-back
matches the requested dimension. An offline or timed-out endpoint triggers at
most one resolver invalidation and fresh descriptor resolution; the retry
rebuilds the RenderingControl transport from the newly resolved control URL.
Adapter errors map to the neutral core failure taxonomy without exposing URLs,
payloads, device identifiers, or fault descriptions.

The signed app links the UPnP module through a private `MediaTargetSession`
actor. The session is created only for a configured UPnP stable identity,
publishes reachability only after a bounded state probe, and discards probe
results from invalidated generations. Preview and unconfigured states never
create a network session. Activation-relevant route changes cancel probe
publication, while equivalent snapshots preserve established health. Sleep and
wake invalidate the resolver lifecycle generation before the next eligible
probe, and an offline target retries when the app next refreshes permission
state. A `NWPathMonitor` observer invalidates resolver and command generations
when the available network path or active interface kinds change. Only the
system path reason `localNetworkDenied` produces Local Network recovery state;
empty discovery and generic transport failure remain inconclusive. Device
authentication rejection has separate target-recovery copy and is never
presented as macOS Local Network denial.

Whether the default macOS path monitor reports `localNetworkDenied` for this
raw multicast discovery path remains a signed-device qualification item. If the
system does not provide that evidence, the app stays on generic offline or empty
recovery copy rather than guessing.

Eligible UPnP volume actions use the existing core queue decision and then enter
a single-consumer app command pump. The pump executes one action at a time
through `MediaTargetCommandExecutor`, keeps the core coordinator transport
neutral, and completes pending capacity only after the physical target returns.
Route mismatch, configuration removal, permission changes, sleep, wake, and
session replacement cancel the pump and invalidate its generation. A stale or
cancelled completion publishes no health; confirmed success remains reachable,
and authentication rejection remains distinct from generic unreachable state.
Diagnostics expose bounded dispatch/failure/recovery counts, coarse network
path state and transition count, and the generic
`local-network` connection kind without target identity, address, URL, model,
failure detail, or protocol payload.

Signed-app discovery wraps SSDP search and descriptor confirmation in the UPnP
module. The app receives only a stable identity plus a deterministic ordinal,
renders generic `Media Renderer N` choices, and requires an explicit selection.
Selection captures the current route, persists only the generic label and
stable identity, replaces the live session without relaunch, and invalidates
the previous resolver generation. Hosts, control URLs, model strings, and raw
discovery failures never cross the adapter boundary.

Both the SSDP `LOCATION` used to fetch a description and any declared
`URLBase` must pass endpoint validation. A safe base never legitimizes an unsafe
description location, and a present but malformed base fails closed.

The module does not touch AppKit or talk to real devices in public tests.
Endpoint, descriptor, SSDP, SOAP, and HTTP safety stay in this module so the
core contract remains transport-neutral. Fault descriptions, response payloads,
and raw SSDP packets are never surfaced; only bounded structured values are
available inside the adapter.

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
