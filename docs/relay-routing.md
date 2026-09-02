# Relay Routing

## Milestone Boundary

Issue #5 adds the first honest routing proof surface: an explicitly labeled
in-process preview target. The current signed app also supports explicit
pairing-free UPnP media-renderer discovery and volume routing. Discovery never
auto-selects a target; the activation rule is captured from the current route
when the user chooses a generic renderer label. Normal Mac volume behavior is
not intercepted or suppressed.

The preview target is removable and resettable from Settings. Its configuration
is stored locally in `UserDefaults` because it contains no credentials or other
secrets. Target names are local UI data and are not copied into diagnostics.

## Architecture

`MediaControlCore` contains the deterministic routing boundary:

- `RelayConfiguration` stores a target kind, local target metadata, and an
  `ActivationRule`.
- `RelayConfigurationFactory` derives a preview rule from the current route.
  Display transports require a display only when its name is related to the
  audio-output name; otherwise the rule uses audio-only matching rather than
  binding to an arbitrary display on a multi-display Mac.
- `RelayRoutingReducer` owns all routing decisions. It consumes configuration,
  permission, route snapshots, observer lifecycle, reachability, and volume
  action events. It emits the resolved state, at most one command, and
  cancellation signals.
- `RelayRecordingPreviewSink` records commands synchronously, preserves order,
  tracks actions that were not recorded, and keeps bounded recent history. Its
  queue policy remains covered with synthetic pending counts for a future
  asynchronous sink; the current in-process sink completes immediately and
  does not accumulate pending depth.

`RelayCoordinator` is a thin `@MainActor` app adapter. It owns one reducer and
one preview sink, applies reducer outputs, cancels the gesture monitor when
requested, and publishes state and activity for SwiftUI. It does not decide
whether a command is eligible.

Physical target work also feeds the pure `MediaTargetPresentationModel`. A
fresh probe establishes a hidden confirmed baseline; an
action enters pending-cold or pending-with-baseline, and only the reachable
outcome correlated to that exact in-flight action may move the confirmed level.
Its local invalidation epoch is
separate from session generations, and configuration, permission, session,
sleep, and route changes clear all cached presentation values before recovery.
Failed, cancelled, timed-out, mismatched, and superseded results never advance
it. The app dismisses terminal presentation after the configured duration while
keeping a throttled, target-agnostic accessible status on the menu-bar item and
menu window. A failed command replaces that value with `Volume control
unavailable`; a later successful command or probe replaces the failure status,
while non-command loss of the active target clears the last confirmed value.
Presentation invalidation also clears it. Held-repeat backlog drops at release,
and the app still presents the already in-flight final confirmation. Target-declared
minimum and maximum values drive normalization,
exact rail feedback, and mute display retention; `volumeStep` remains capability
metadata for command planning and validation rather than presentation scaling.
The presentation model has no AppKit, transport, target identity, or hardware
dependency.

## Lifecycle

Commands require all of the following:

1. a configured and supported preview target;
2. granted Input Monitoring permission;
3. an observing route observer with a current activation match; and
4. a reachable preview sink.

Any transition out of `active` immediately cancels held gestures and pending
sink capacity. Route mismatch, permission loss, observer suspension or stop,
unknown route matching, and configuration removal therefore stop recording
without waiting for a timer. Suspended and stopped observation invalidate the
cached activation match. The reducer is timer-free; gesture timing remains in
the existing bounded gesture monitor.

Presentation state is hidden on configuration, permission, and session
invalidation; it becomes suspended during sleep and route-lost on a route
mismatch. Wake and recovery require a fresh probe or a newer command
confirmation before a level is displayed again.

State precedence is `unconfigured`, `unsupported`, `needsPermission`, route
matching, then target reachability. Target reachability distinguishes
`needsLocalNetworkPermission`, `targetAuthenticationRejected`,
`checkingTarget`, `offline`, and `active`. Unknown reachability is
`checkingTarget`, never `offline`. An explicit system-path denial is
authoritative. The denial-compatible error observed on the initial SSDP
multicast send remains Local Network denial while the system path is unknown or
available, is demoted to offline when the path is unavailable, and is never
inferred from an empty discovery result.

## Status And Diagnostics

Status copy is keyed by `RelayState` and target kind. Preview active copy says
that commands are being recorded or relayed to a preview target, that no media
device is connected or controlled, and that the Mac continues handling volume
normally. The checking-target state has distinct copy and an icon.

Diagnostics are allowlisted to coarse fields: `target_kind`, `activation`,
command and recovery counts, `target_connection`, `network_path`, and
`network_transitions`, plus the existing build, permission, route observation,
transport kind, and active display count fields. They never include route names,
audio/display UIDs or UUIDs, target labels, interface names, addresses,
credentials, errors, or raw events. Preview connection status is
`preview-sink`; without a configured target it is `not-available`.

## Manual Qualification Boundary

Automated tests cover state precedence, Codable configuration, route-derived
matching, reducer cancellation and sequence behavior, sink ordering and
backpressure, preview status honesty, and diagnostics privacy. Manual
qualification uses a signed macOS app run to verify permission recovery, real
volume-key observation, route changes, sleep/wake cancellation, target
creation/removal, and the Settings counters.

The August 25, 2026 direct-build run confirmed:

- an active display-audio route recorded an isolated physical Up, Down, Mute,
  and Mute sequence as 8 events, 4 actions, and 4 commands with no unrecorded
  action;
- physical Up and Down holds stopped without any count growth across a second
  diagnostic snapshot three seconds after release;
- switching to built-in speakers produced `dormant` and `activation=no-match`;
- one isolated physical Up tap on the built-in route changed normal Mac volume
  from 25 to 31, emitted one action, recorded no command, and counted one
  unrecorded action; and
- returning to display audio produced a fresh `active` and
  `activation=match` snapshot; and
- controlled real sleep produced dormant state during dark wake, preserved the
  app process and exact 132/66/65/1 event/action/command/unrecorded counters,
  then returned to observing active state on full wake. A physical Up/Down pair
  after wake added exactly 4 events, 2 actions, and 2 commands.

AirPlay was unavailable during the run. Normal TV standby kept the HDMI display
and audio route online, so it was not evidence of detach behavior. The physical
built-in/display-audio transition and deterministic lifecycle tests cover the
route-loss behavior required by this milestone. AirPlay and optional
display-absent diagnostics are deferred to issue #23.

No real device, Samsung transport, network, pairing, or credential behavior is
claimed by this milestone.

## External Custom URL Actions

The menu-bar app registers one custom URL scheme with two exact host families.
The volume actuator remains `media-control-relay://control/volume/up`,
`media-control-relay://control/volume/down`, and
`media-control-relay://control/volume/mute`. The Apple remote actuator is the
exact allowlist of `media-control-relay://remote/navigate/up`,
`media-control-relay://remote/navigate/down`,
`media-control-relay://remote/navigate/left`,
`media-control-relay://remote/navigate/right`, `media-control-relay://remote/select`,
`media-control-relay://remote/back`, `media-control-relay://remote/home`,
`media-control-relay://remote/play-pause`, `media-control-relay://remote/previous`,
`media-control-relay://remote/next`, `media-control-relay://remote/seek/forward/10`,
`media-control-relay://remote/seek/forward/30`, `media-control-relay://remote/seek/backward/10`,
`media-control-relay://remote/seek/backward/30`, `media-control-relay://remote/volume/up`,
and `media-control-relay://remote/volume/down`. The app delegate accepts only
those exact strings, rejects alternate casing, percent encoding, credentials,
ports, queries, fragments, unknown hosts, and extra path components, and never
logs the raw URL.

Cold-launch URL delivery is held until `RelayAppModel` is available. Delivery
does not itself request window presentation or activation; normal first-run
setup behavior remains unchanged. Accepted actions enter the same non-physical
dispatch path used by menu controls with held-repeat disabled and physical-input
counters untouched. A monotonic-time duplicate limit runs before the reducer;
rejected and rate-limited totals are coarse diagnostics only.

The two hosts are separate, host-based no-fallback boundaries. `control` volume
URLs never fall through to the `remote` parser, and `remote` URLs never fall
back to the volume actuator. Parsing is strict and exact, not prefix-based or
path-normalizing.

The local actuator is bounded and intentionally narrow. It exposes only the
documented local actions, does not identify callers, does not authorize local
processes, and does not create a path to arbitrary remote commands. Unsupported
or unavailable actions fail closed with an honest rejected state instead of an
automatic fallback.

The later signed pairing-free Samsung UPnP matrix is recorded separately in
[`samsung-upnp-qualification.md`](samsung-upnp-qualification.md). That record
does not broaden this milestone's preview-target claims.
