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

State precedence is `unconfigured`, `unsupported`, `needsPermission`, route
matching, then target reachability. Target reachability distinguishes
`needsLocalNetworkPermission`, `targetAuthenticationRejected`,
`checkingTarget`, `offline`, and `active`. Unknown reachability is
`checkingTarget`, never `offline`; Local Network denial requires an explicit
system path reason and is never inferred from an empty discovery result.

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

The later signed pairing-free Samsung UPnP matrix is recorded separately in
[`samsung-upnp-qualification.md`](samsung-upnp-qualification.md). That record
does not broaden this milestone's preview-target claims.
