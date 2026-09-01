# Samsung UPnP Qualification

## Scope

This record covers the signed pairing-free UPnP `RenderingControl:1` proof for
milestone `0.2 — Samsung Control Proof`. It applies only to Samsung model
`UN65JU670D`, a 2015 JU-series television. The model was identified on
August 27, 2026 from the device's public UPnP `manufacturer`,
`modelDescription`, and `modelName` fields.

This identification names the tested hardware. No other Samsung model, series,
firmware, or RVU feature is claimed as supported.

Power control, navigation, apps, source selection, pairing, credentials, and
untested Samsung models remain outside this proof.

## Qualified Artifact

The August 28 and August 30, 2026 qualification runs used the Release build from
merged commit `4c907bf`. PR #51 added Local Network denial classification, and
PR #52 preserved that denial while the initial network-path snapshot is
unsettled. The app was installed at `/Applications/Media Control Relay.app` and
retained its existing bundle identifier and Developer ID identity.

The artifact passed:

- strict deep code-sign verification;
- Gatekeeper assessment with source `Developer ID`;
- configuration and Input Monitoring persistence after replacement; and
- active target resolution without pairing or stored Samsung credentials.

The previously installed signed app was preserved locally before replacement
as a rollback candidate. The rollback candidate and merged build were each
installed, verified, launched to an active zero-counter state, and replaced in
the intended direction. The merged build remains installed.

## Capability And Command Evidence

The run recorded only privacy-safe route state and counters. No actual target
volume, host, address, identifier, endpoint, or service-description content was
copied. The public model name in this document was obtained separately and is
not part of app diagnostics.

- **Route gate:** Bluetooth audio produced `dormant` and
  `activation=no-match` with zero target commands. The configured display-audio
  route produced `active` and `activation=match` before target testing.
- **Normal step:** one brief Volume Down produced 2 raw events, 1 action,
  1 recorded command, 1 dispatched target command, and 0 failures. The TV
  visibly moved by one normal step.
- **Low rail:** one bounded hold reached the minimum and stopped after release.
  After a clean app relaunch, one exact Down produced 2 events, 1 action,
  1 recorded command, 1 app-level dispatch, and 0 failures. The executor read
  the live renderer state, planned no change at the minimum, and sent no SOAP
  `SetVolume` write.
- **High rail:** three bounded holds traversed the renderer-declared range with
  105 actions, no unrecorded actions, and no target failures. After a clean app
  relaunch, one exact Up produced 2 events, 1 action, 1 recorded command,
  1 app-level dispatch, and 0 failures. The executor read the live renderer
  state, planned no change at the maximum, and sent no SOAP `SetVolume` write.
- **Out-of-band change:** the TV remote changed volume independently without
  changing app counters. One exact Mac Volume Up then added 2 events, 1 action,
  1 recorded command, 1 dispatched command, and 0 failures. The TV visibly
  advanced one valid step from the independent state.
- **Discrete mute and unmute:** the keyboard-correct `Fn+Mute` chord visibly
  muted and unmuted the TV. The initial apparent miss was user input error on a
  keyboard mode that requires Fn for media keys. An isolated correct press
  decoded as `Mute`, produced one target dispatch with zero failures, and was
  confirmed by TV read-back.
- **Mute read-back:** exact merged-source mute and unmute operations confirmed
  both requested states, preserved the pre-mute volume, and restored the
  original state.
- **Route mismatch:** on built-in audio, one physical Volume Down used native
  Mac handling, increased `actions_not_recorded` by one, and added zero target
  dispatches. The configured display route was then restored.
- **Held input:** a private packet capture of the physical held-volume sample
  recorded four complete command/response operations at approximately 61.8,
  63.0, 74.1, and 85.3 ms. The bounded held-key transport p95 was 85.3 ms,
  below the 150 ms target. The private capture is uncommitted and unpublished.
- **Source mode:** the qualified source mode is Mac display audio routed to the
  Samsung display in HDMI/display mode. Other source and input modes are not
  claimed.

Successful state-changing target commands include the implementation's
requested-dimension read-back check. A socket write or HTTP completion alone is
not counted as success. Rail presses instead complete after a live renderer
state read produces a client-side no-change plan.

## Lifecycle And Recovery Evidence

App relaunch, sleep/wake, standby, standby recovery, and network-transition
evidence below was collected on the signed merged build at commit `3758c13`.
Local Network and TV mains-loss/cold-boot evidence names the later build where
it was collected.

- **App relaunch:** clean relaunches preserved the configured target, Input
  Monitoring grant, active route match, and target reachability.
- **Sleep and wake:** a controlled software sleep entered deep idle and woke
  six seconds later. Event, action, command, and failure counters remained zero
  through the cycle. The network observer recorded the expected two
  transitions, the relay returned to `active`, and one exact post-wake Volume
  Down produced 2 events, 1 action, 1 recorded command, 1 dispatched command,
  and 0 failures.
- **TV standby:** one exact Volume Down while the TV was in normal standby
  produced one recorded and dispatched command, one target failure, and an
  explicit `offline` state. The app did not claim success.
- **Standby recovery:** after the TV returned, the relay moved from `offline`
  through `checking-target` to `active` without pairing or a manual recovery
  action. One exact Volume Down then succeeded with one recorded and dispatched
  command and no additional failure.
- **Network transition:** disabling the primary Ethernet service moved the
  network transition counter from 0 to 1 while Wi-Fi preserved an available
  path. Restoring Ethernet moved the counter to 2. The relay remained active,
  counters remained otherwise zero, and one exact post-rejoin Volume Down
  succeeded with 2 events, 1 action, 1 recorded command, 1 dispatched command,
  and 0 failures.
- **Local Network denial:** a Developer ID permission-isolated probe built from
  exact final commit `4c907bf` was granted temporary Input Monitoring through
  System Settings. With only that probe's Local Network toggle OFF, a clean
  route-matched launch reported `needs-local-network-permission` while
  `network_path=available`; all command, action, dispatch, and failure counters
  remained zero.
- **Local Network recovery:** turning the same toggle ON and merely activating
  the probe returned it automatically to `active` with matched display route,
  successful target state read-back, no reconfiguration, no manual recovery
  count, and zero failures. The temporary app, defaults, and Input Monitoring
  grant were then removed, and the final production build was restored.
- **TV mains loss and display detach:** removing TV mains power safely removed
  the Samsung display from macOS, changed the active-display count from 2 to 1,
  moved audio to the built-in transport, and put the relay in `dormant` with
  `activation=no-match`. The app did not dispatch work to the absent target.
- **TV cold boot and display reattach:** restoring mains power returned the
  display route and `activation=match`. The first early target probe reported
  `offline` while the TV services were still starting. After a 15-second
  warm-up, ordinary app activation retried the probe and returned the retained
  configuration to `active` without pairing, reconfiguration, a manual recovery
  action, or a target failure.
- **Post-cold-boot command:** one exact physical Volume Down produced the
  expected two input events, one action, one recorded command, and one target
  dispatch. The TV visibly responded, requested-dimension read-back completed,
  and the target failure count remained zero.

Earlier signed evidence recorded in issue #21 on August 27, 2026 used build
`1f8722c`. The restart check was repeated on August 30 with the strict-valid,
Gatekeeper-accepted Developer ID build from final implementation commit
`4c907bf`. Before restart, the retained configuration was `active` and
route-matched with Input Monitoring granted, local-network target connection,
and zero event, action, command, dispatch, failure, and recovery counters. The
boot time advanced from August 27 at 17:47:35 local time to August 30 at
12:31:32 local time.

The one-shot login observer's first attempt stopped before app launch because
its minimal environment could not find the Homebrew `rg` helper. That missing
command made the Gatekeeper pipeline return false and the local log recorded
`gatekeeper-not-developer-id`; this was an observer false negative, not an
artifact result. Strict verification and Gatekeeper assessment passed before
restart and in the corrected manual check on the new boot.

The build-4 qualification below predates app-managed launch at login. Build 6
introduces the supported `SMAppService.mainApp` path; automatic launch behavior
requires separate signed-app qualification before the legacy prototype
LaunchAgent is retired.

After the observer was changed to use the system `/usr/bin/grep`, it was invoked
manually during the same login, about 15 minutes after boot. It issued an app
open request, verified that exactly one app process was running afterward, and
recorded retained configuration, Input Monitoring, route match, local-network
target connection, and `active` state with all counters still zero. The evidence
does not establish whether the app was already running before that request. It
proves warm-boot recovery of retained configuration, permission, route match,
and target reachability following a manual observer invocation; it does not
claim automatic launch-at-login behavior, which remains part of signed
local-alpha cutover qualification.

An accidental post-restart media-key hold then produced 20 events, 10 actions,
10 recorded commands, and 10 target dispatches with no unrecorded action,
failure, or recovery attempt. One subsequent exact physical Volume Down added
the expected two events, one action, one recorded command, and one target
dispatch. Volume Down was the last detected action, the relay remained
`active`, and all failure and recovery counters remained zero. A filtered local
accessibility read-back recorded **Last Detected** as **Volume Down** without
capturing target or host details.

Physical mute, route mismatch, and held-key evidence was refreshed on signed
commit `f802745`. The final `4c907bf` delta changes only Local Network
reachability classification, its regression test, and matching documentation;
it does not change media-key decoding, command queueing, UPnP volume/mute
operations, or successful-command read-back behavior.

## Privacy Audit

Copied diagnostics matched the enforced diagnostics allowlist summarized in
`docs/relay-routing.md`. An additional pattern check found no URL, IP address,
UUID, host, device identifier, model field, control URL, or SCPD content. The
manual procedure names generic Ethernet and Wi-Fi transport types, but those
names are not present in copied diagnostics.

The evidence intentionally omits:

- target host and network-interface names;
- device UUID, UDN, serial number, and stable identifier;
- model strings beyond the single public qualification target named above;
- control and service-description URLs;
- raw SSDP, device-description, SCPD, SOAP, or pairing responses; and
- actual target volume values.

## Review And Remaining Gate

Opus and a Gemini-family reviewer approved the final Local Network code changes
after requested corrections were resolved. The current-build warm-restart
evidence and explicit build attribution for older lifecycle checks are now
recorded above and await final evidence review. JetBrains inspection reported no
semantic findings; its reported items were spellcheck-only URL schemes, SF
Symbol names, protocol tokens, and fixture bundle IDs.

Milestone 0.2 remains open pending:

- publication of the complete privacy-safe exit record in issue #21; and
- final non-empty Opus and Gemini-family approval of that completed evidence and
  bounded compatibility scope.
