# Route Observation

Last updated: August 25, 2026.

Issue #4 adds the observation slice used by the routing coordinator for the
current macOS route. It provides an honest, deterministic activation input
without changing the selected system output. The milestone-0.1 preview sink
may record commands after the reducer confirms that route, permission, observer
lifecycle, and sink state are eligible; no device commands are sent.

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

The latest snapshot is available to `RelayAppModel` and is routed through the
pure `RelayRoutingReducer`. Suspended and stopped observation invalidate the
cached activation match immediately, so a preview target cannot continue
recording while observers are asleep or stopped.

## Qualification Boundary

Deterministic package tests cover normalization, equality suppression,
coalescing, lifecycle idempotence, wake refresh semantics, privacy-safe
diagnostics, and activation bridging. Physical HDMI, AirPlay/HomePod, display
attach/detach, and real sleep/wake behavior remain manual qualification work;
this issue does not claim evidence for those environments.
