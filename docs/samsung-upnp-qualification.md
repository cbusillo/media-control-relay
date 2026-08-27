# Samsung UPnP Qualification

## Scope

This record covers the signed pairing-free UPnP `RenderingControl:1` proof for
milestone `0.2 — Samsung Control Proof`. It applies only to Samsung model
`UN65JU670D`, a 2015 JU-series television. The model was identified on
August 27, 2026 from the device's public UPnP `manufacturer`,
`modelDescription`, and `modelName` fields.

This identification names the tested hardware; it does not complete the
compatibility claim. No other Samsung model, series, firmware, or RVU feature
is claimed as supported.

Power control, navigation, apps, source selection, pairing, credentials, and
untested Samsung models remain outside this proof.

## Qualified Artifact

The August 27, 2026 run used the Release build from merged commit `3758c13`.
The app was installed at `/Applications/Media Control Relay.app` and retained
its existing bundle identifier and Developer ID identity.

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

Successful state-changing target commands include the implementation's
requested-dimension read-back check. A socket write or HTTP completion alone is
not counted as success. Rail presses instead complete after a live renderer
state read produces a client-side no-change plan.

## Lifecycle And Recovery Evidence

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

Earlier signed evidence recorded in issue #21 on August 27, 2026 used build
`1f8722c`. It covers warm Mac restart, TV mains-loss and cold-boot recovery,
discrete mute, route mismatch with normal Mac volume behavior, and warmed
held-key p95 latency of 98 ms. Those checks were not re-run after capability
commit `3758c13`; they remain dated supporting evidence rather than current-
build measurements. The merged-build run adds renderer-declared range, bounded
held input without a new latency sample, rail, read-back, standby,
network-transition, privacy, and rollback evidence.

## Privacy Audit

Copied diagnostics matched the exact allowlist documented in
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

Issue #37 closed after final Opus review approved the merged capability
implementation and signed rail/read-back evidence. Repeated Gemini-family runs
returned no output and were recorded as unavailable rather than approval.

The tested model is now named safely, but milestone 0.2 remains open. The
remaining exit evidence is:

- re-run discrete mute/unmute, route mismatch with normal Mac handling, and a
  held-key p95 sample on the current merged qualification build;
- record local-network denial/regrant behavior and a source/input-mode sample;
- record whether mute read-back preserves the pre-mute volume or returns zero;
- scope the display detach/reattach criterion as unavailable on this hardware
  unless an actual detach can be produced safely;
- publish the complete reproducible exit record in issue #21, distinguishing
  current-build evidence from dated supporting evidence; and
- obtain final Opus and Gemini-family approval. Empty Gemini-family results are
  unavailable evidence, not approval.
