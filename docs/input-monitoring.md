# Input Monitoring Probe

Last updated: August 25, 2026.

This probe determines whether Media Control Relay can passively observe Volume
Up, Volume Down, and Mute in both direct and sandboxed macOS builds. The
listen-only monitor does not suppress normal macOS behavior. When the explicit
preview target is configured and active, the resulting internal actions are
recorded by the in-process preview sink; they are never sent to a device.

## Implementation Boundary

- The event tap is restricted to system-defined events and uses listen-only
  mode.
- Typed keys are never delivered to the app.
- `MediaControlCore` decodes plain event payloads and bounds repeat behavior;
  the app adapter drives those deadlines before emitting `VolumeAction` values.
- The app stores only aggregate event counts and the latest supported action for
  local setup feedback.
- Public diagnostics omit raw event payloads, timings, and device identifiers.

## Runtime Matrix

| Build | Sandbox | Signing | Permission | Tap created | Keys observed | Result |
| --- | --- | --- | --- | --- | --- | --- |
| Release | No | Developer ID Application, team `MM5YXC7T6E` | Prior fresh grant survived signed rebuilds, relaunches, and one warm host reboot | Yes | 8 isolated physical events produced 4 actions and 4 recorded commands; physical holds stopped after release; synthetic missed release stopped at 25 actions | Signed direct physical integration path is viable; sleep/wake and fresh TCC recovery remain |
| AppStore local probe | Yes | Developer ID Application with AppStore entitlements and probe bundle ID | Prior fresh grant survived the current signed rebuild and relaunch | Yes | 8 synthetic events produced 4 actions and 4 recorded commands | Local sandbox integration path is viable; physical keys and App Store distribution remain unproven |

## Test Environment

- Date: August 25, 2026.
- Host: Apple silicon Mac running macOS 27.0 build `26A5421a`.
- Toolchain: Xcode 27.0 build `27A5194q`.
- Direct bundle: `com.shinycomputers.media-control-relay`, signed with Developer
  ID Application for team `MM5YXC7T6E` and hardened runtime enabled.
- Sandbox probe: AppStore configuration copied to the distinct local bundle ID
  `com.shinycomputers.media-control-relay.sandbox-probe`, signed with the same
  Developer ID identity and the checked-in AppStore entitlements.
- Both installed bundles passed `codesign --verify --deep --strict`.
- The direct bundle had no application entitlements. The sandbox probe had only
  `com.apple.security.app-sandbox` and
  `com.apple.security.network.client`; neither bundle had
  `com.apple.security.get-task-allow`.
- Both bundles used hardened runtime and passed local Gatekeeper assessment as
  Developer ID applications.

## Product Identity Migration

- The GitHub repository and local checkout were renamed to
  `media-control-relay`.
- The direct bundle moved from `com.shinycomputers.tv-volume-bridge` to
  `com.shinycomputers.media-control-relay`.
- The sandbox probe moved from
  `com.shinycomputers.tv-volume-bridge.sandbox-probe` to
  `com.shinycomputers.media-control-relay.sandbox-probe`.
- The old development app, preference domain, sandbox container, and Input
  Monitoring records were removed. The separate working `Samsung TV Volume`
  prototype was intentionally left untouched pending the cutover tracked in
  issue #8.
- Both renamed identities completed a fresh request, enable, quit/reopen, and
  event-observation flow under the new product name.
- Public diagnostics renamed `bridge_state` to `relay_state` and
  `tv_connection` to `target_connection`; both remain aggregate state fields
  without target identity or address data.

## Runtime Findings

- In the August 24 identity-migration probe, `tccutil reset ListenEvent`
  produced a fresh permission flow for each bundle identifier. The app showed
  not-set-up guidance before the request and request-pending guidance after the
  request. A denied request is distinguished after relaunch, when the public
  preflight API still reports no grant.
- Input Monitoring became effective after the app was quit and reopened, as
  required by the macOS permission UI. Both builds then reported that volume
  key access was ready, which also proves that the listen-only event tap was
  created successfully.
- A synthetic integration probe posted system-defined press/release pairs for
  Volume Up, Volume Down, Mute, and a second Mute that restored the prior mute
  state. Both installed builds reported 8 observed events, 4 emitted actions,
  and 4 recorded preview commands with no unrecorded actions.
- A separate synthetic missed-release probe posted one Volume Up press without
  a release. The final direct build emitted 25 bounded actions (the initial
  action plus 24 policy repeats) and then stopped without further input. A
  release and one balancing Volume Down pair restored the synthetic volume
  step.
- After a warm host reboot, rebuilding and relaunching the same Developer ID
  bundle identity preserved Input Monitoring authorization. The rebuilt app
  recreated its event tap, restored the saved preview target, and returned to
  active route matching without a new permission request.
- An isolated physical Volume Up, Volume Down, Mute, and second Mute sequence on
  the active display-audio route produced exactly 8 observed events, 4 emitted
  actions, 4 recorded preview commands, and 0 unrecorded actions.
- A physical Volume Up hold produced 27 observed events and 4 actions. A later
  Volume Down hold added 46 events and 7 actions. For each hold, two diagnostic
  snapshots taken three seconds apart were identical after release, proving
  that no repeat continued after the physical key was released. Three later
  quick Volume Up taps added exactly 6 events and 3 actions.
- Switching the default output from display audio to built-in speakers changed
  the relay to `dormant` with `activation=no-match`. One isolated physical
  Volume Up tap changed normal Mac output volume from 25 to 31 while producing
  2 observed events, 1 emitted action, 0 recorded preview commands, and 1
  unrecorded action. A second snapshot three seconds later was unchanged.
  Returning to the display-audio output restored `active` with
  `activation=match` from a fresh route snapshot.
- No AirPlay or HomePod output was exposed as a selectable Core Audio device
  during this qualification window, so no AirPlay behavior is claimed.
- Normal TV standby did not constitute a display detach on this hardware:
  macOS continued reporting the display online and primary, and the selected
  display-audio route remained present. A later physical power disconnect and
  reconnect occurred, but relay diagnostics were not captured while the
  display was absent, so true detach-state behavior remains open.
- During the direct probe, macOS still displayed its normal output-device HUD,
  labeled Samsung for the active audio device, after a synthetic Volume Up
  event while the monitor was active. A matching Volume Down event restored the
  prior level. This agrees with the `.listenOnly` tap configuration and the
  callback returning the original event.
- The synthetic probe validates deterministic edge cases; the separate
  physical-key run above confirms the signed direct runtime on release
  hardware.
- Copied diagnostics expose only coarse preview target kind, activation,
  recorded-command and unrecorded-action counts, sink availability, transport
  kind, and active display count. They never include route names, UIDs, UUIDs,
  target labels, or raw events.
- Duplicate suppression applies to repeated press events without an intervening
  release. A complete second press/release pair is treated as a deliberate
  rapid press rather than discarded.
- Setup and Settings remained unclipped in native dark and light appearances.
  The Accessibility tree preserved visible button names and supplemental hints.
- With full keyboard navigation enabled temporarily, Tab reached the setup link
  and the Settings preview-target button; Space activated both controls. The
  original global keyboard-navigation setting was restored afterward.
- The app has no custom animation or transition APIs, so reduced-motion mode has
  no app-authored motion to suppress in this milestone.

## App Store Feasibility

- A local `AppStore` archive completed under automatic signing, but Xcode signed
  it with an Apple Development identity and embedded no provisioning profile.
- No installed provisioning profile matches
  `com.shinycomputers.media-control-relay`.
- Exporting that archive with method `app-store-connect` failed reproducibly
  with `No profiles for 'com.shinycomputers.media-control-relay' were found`.
- Decision: the local sandbox path is viable, but a real Mac App Store or
  TestFlight build remains blocked on provisioning and subsequent Apple review.
  This does not block the Developer ID product path.

## Decision

The signed direct physical event-tap integration path and the synthetic local
sandbox path are **viable on the tested macOS build**. Physical keys, holds,
relaunches, one warm reboot, and built-in/display-audio route switching passed
for the direct build. This is not evidence of physical-key behavior in an App
Store-signed build, Mac App Store profile acceptance, TestFlight behavior, App
Review acceptance, or behavior after a storefront update. Those checks remain
part of later distribution qualification.

## Required Checks

- Completed: fresh permission request, recovery guidance, grant, and relaunch.
- Completed: synthetic Volume Up, Volume Down, and Mute press/release
  observation in both signed configurations.
- Completed: unit coverage for repeat cadence, duplicate presses, release
  settling, queue backpressure, and missed-release bounds.
- Completed: the live app adapter feeds decoded events through the bounded
  gesture tracker before emitting internal `VolumeAction` values.
- Runtime note: the missed-release repeat limit is live. Preview recording is
  local and synchronous, so the app sink completes each command immediately
  and does not accumulate pending depth; synthetic tests retain queue-policy
  coverage for future asynchronous sinks.
- Completed: relaunch with the same signing identity preserved permission and
  recreated observation without duplicate presses.
- Completed: one warm host reboot followed by a same-identity rebuild retained
  Input Monitoring and restored active observation.
- Completed: isolated physical Volume Up, Volume Down, Mute, and Mute
  press/release observation on the signed direct build.
- Completed: physical Volume Up and Volume Down hold/release behavior stopped
  without post-release growth.
- Completed: live built-in-speaker and display-audio transitions produced
  dormant/no-match and active/match respectively, while the built-in route kept
  normal Mac volume handling and recorded no preview command.
- Completed: local sandbox behavior is documented with exact build evidence.
- Completed: dark/light appearance, Accessibility naming, keyboard activation,
  and reduced-motion source review.
- Completed: the App Store path is classified as locally sandbox-viable but not
  distribution-qualified because no matching profile exists.
- Unavailable in this environment: an AirPlay or HomePod output, so no live
  AirPlay route claim is made.
- Remaining manual evidence: true display detach with relay state captured
  during the absence, real sleep/wake, VoiceOver judgment, increased-contrast
  judgment, and a fresh TCC reset/regrant when interrupting the current grant
  is acceptable.
- Remaining distribution evidence: a real App Store or TestFlight-signed build
  when a matching profile exists.
- The sleep/wake check must verify that `NSEvent.timestamp` and system-uptime
  deadline scheduling remain aligned so a held key neither repeats immediately
  nor stalls after wake.
