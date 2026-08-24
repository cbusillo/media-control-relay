# Input Monitoring Probe

Last updated: August 24, 2026.

This probe determines whether TV Volume Bridge can passively observe Volume Up,
Volume Down, and Mute in both direct and sandboxed macOS builds. It does not
send TV commands or suppress normal macOS behavior.

## Implementation Boundary

- The event tap is restricted to system-defined events and uses listen-only
  mode.
- Typed keys are never delivered to the app.
- `VolumeBridgeCore` decodes plain event payloads and bounds repeat behavior;
  the app adapter drives those deadlines before emitting `VolumeAction` values.
- The app stores only aggregate event counts and the latest supported action for
  local setup feedback.
- Public diagnostics omit raw event payloads, timings, and device identifiers.

## Runtime Matrix

| Build | Sandbox | Signing | Permission | Tap created | Keys observed | Result |
| --- | --- | --- | --- | --- | --- | --- |
| Release | No | Developer ID Application, team `MM5YXC7T6E` | Fresh reset, request, enable, relaunch | Yes | Synthetic Volume Up, Volume Down, and Mute press/release pairs | Synthetic integration path is viable; physical-key confirmation remains |
| AppStore local probe | Yes | Developer ID Application with AppStore entitlements and probe bundle ID | Fresh reset, request, enable, relaunch | Yes | Synthetic Volume Up, Volume Down, and Mute press/release pairs | Local sandbox integration path is viable; physical keys and App Store distribution remain unproven |

## Test Environment

- Date: August 24, 2026.
- Host: Apple silicon Mac running macOS 27.0 build `26A5416b`.
- Toolchain: Xcode 27.0 build `27A5194q`.
- Direct bundle: `com.shinycomputers.tv-volume-bridge`, signed with Developer
  ID Application for team `MM5YXC7T6E` and hardened runtime enabled.
- Sandbox probe: AppStore configuration copied to the distinct local bundle ID
  `com.shinycomputers.tv-volume-bridge.sandbox-probe`, signed with the same
  Developer ID identity and the checked-in AppStore entitlements.
- Both installed bundles passed `codesign --verify --deep --strict`.
- The direct bundle had no application entitlements. The sandbox probe had only
  `com.apple.security.app-sandbox` and
  `com.apple.security.network.client`; neither bundle had
  `com.apple.security.get-task-allow`.

## Runtime Findings

- `tccutil reset ListenEvent` produced a fresh permission flow for each bundle
  identifier. The app showed not-set-up guidance before the request and
  request-pending guidance after the request. A denied request is distinguished
  after relaunch, when the public preflight API still reports no grant.
- Input Monitoring became effective after the app was quit and reopened, as
  required by the macOS permission UI. Both builds then reported that volume
  key access was ready, which also proves that the listen-only event tap was
  created successfully.
- A synthetic integration probe posted system-defined press/release pairs for
  Volume Up, Volume Down, and Mute. Both installed builds reported three
  detected presses and Mute as the final action.
- A separate synthetic missed-release probe posted one Volume Up press without
  a release. The final direct build emitted 25 bounded actions (the initial
  action plus 24 policy repeats) and then stopped without further input.
- During the direct probe, macOS still displayed its normal output-device HUD,
  labeled Samsung for the active audio device, after a synthetic Volume Up
  event while the monitor was active. A matching Volume Down event restored the
  prior level. This agrees with the `.listenOnly` tap configuration and the
  callback returning the original event.
- The synthetic probe validates the event-tap boundary but is not a substitute
  for a final physical-key smoke test on release hardware.
- Copied diagnostics from the final signed direct build preserved only the
  aggregate `volume_events_observed=2` and `volume_actions_emitted=1` counters;
  neither field was redacted or exposed raw event data.
- Duplicate suppression applies to repeated press events without an intervening
  release. A complete second press/release pair is treated as a deliberate
  rapid press rather than discarded.

## Decision

The synthetic event-tap integration path is **viable in a local signed
sandbox** on the tested macOS build. Physical media-key observation remains
required before issue #3 can be closed. This is also not evidence of Mac App
Store profile acceptance, TestFlight behavior, App Review acceptance, or
behavior after a storefront update. Those checks remain part of later
distribution qualification.

## Required Checks

- Completed: fresh permission request, recovery guidance, grant, and relaunch.
- Completed: synthetic Volume Up, Volume Down, and Mute press/release
  observation in both signed configurations.
- Completed: unit coverage for repeat cadence, duplicate presses, release
  settling, queue backpressure, and missed-release bounds.
- Completed: the live app adapter feeds decoded events through the bounded
  gesture tracker before emitting internal `VolumeAction` values.
- Runtime note: the missed-release repeat limit is live. Command-queue
  backpressure remains unit-tested with synthetic pending counts until issue #5
  provides the real queue depth.
- Completed: relaunch with the same signing identity preserved permission and
  recreated observation without duplicate presses.
- Completed: local sandbox behavior is documented with exact build evidence.
- Remaining distribution evidence: physical-key smoke test, sleep/wake, and a
  real App Store or TestFlight-signed build when a matching profile exists.
- The sleep/wake check must verify that `NSEvent.timestamp` and system-uptime
  deadline scheduling remain aligned so a held key neither repeats immediately
  nor stalls after wake.
