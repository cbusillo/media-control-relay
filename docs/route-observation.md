# Route Observation

Last updated: August 25, 2026.

Issue #4 adds a read-only observation slice for the current macOS route. It is
intended to provide the future routing coordinator with an honest, deterministic
activation input without changing the selected system output or sending target
commands.

## Observation Boundary

`MediaControlRelayApp/SystemRouteObserver.swift` owns public macOS APIs:

- Core Audio's default system output property listener and output-device
  properties for the current name, transport kind, and in-memory UID;
- `NSScreen.screens` and `NSApplication.didChangeScreenParametersNotification`
  for connected, active displays;
- `NSWorkspace` sleep and wake notifications.

`MediaControlCore/RouteObservation.swift` owns the platform-independent
`RouteSnapshot` model, text normalization, active-display filtering,
stable-identifier-aware equality, bounded coalescing, lifecycle transitions,
coarse diagnostics, and `ActivationSnapshot` bridging.

## Lifecycle

The observer starts once during model initialization. Repeated `start` and
`stop` calls are no-ops after the first transition. Before sleep it removes the
audio and display listeners, keeps the workspace wake listener active, cancels
pending refresh/coalescing tasks, and asks the model to cancel pending volume-key
gestures. On wake it re-registers route listeners and publishes one fresh
snapshot. A later platform callback may publish a distinct snapshot if the route
actually changed during wake processing.

## Privacy and Diagnostics

Audio UIDs, display IDs/serials, raw audio/display names, hosts, and other device
identifiers never enter diagnostics or logs. Copied diagnostics expose only:

- route observation state (`stopped`, `observing`, or `suspended`);
- coarse audio transport kind;
- active display count.

The latest snapshot is available to `RelayAppModel` for read-only status and for
the future activation coordinator. This change intentionally does not resolve
`relayState` to `active` or `dormant` and does not add a command sink.

## Qualification Boundary

Deterministic package tests cover normalization, equality suppression,
coalescing, lifecycle idempotence, wake refresh semantics, privacy-safe
diagnostics, and activation bridging. Physical HDMI, AirPlay/HomePod, display
attach/detach, and real sleep/wake behavior remain manual qualification work;
this issue does not claim evidence for those environments.
