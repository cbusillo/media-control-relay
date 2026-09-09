# Product Scope

MCR remains a native Mac keyboard volume/mute router. Bitfocus Companion and
Home Assistant take responsibility for explicit control-surface actions and
home automation. MCR itself is retained, not scheduled for uninstallation.

## Retained MCR Responsibilities

- Observe physical volume/mute keys and match the active audio/display route.
- Preserve normal Mac volume behavior when the Samsung route is not active.
- Control compatible Samsung renderers directly through UPnP, with live bounds,
  serialized dispatch and requested-dimension read-back.
- Preserve held-key cancellation, bounded queues, permission recovery,
  sleep/wake handling, offline state and startup behavior.
- Keep the native setup, status and diagnostics needed to operate that path.

Keyboard volume must remain useful when HA or Companion is unavailable. Do not
replace the retained Samsung transport with calls through either service.

## Responsibilities Outside MCR

| Owner | Responsibility |
| --- | --- |
| Bitfocus Companion | Loupedeck pages, encoders, explicit controls and macros |
| Separate Apple TV module | Companion Apple TV session, actions and packaging |
| Home Assistant | Devices, automation and explicit Samsung controls |
| Native Mac actions | Ordinary app launchers and other explicit local actions |
| Operations repo | Local configuration, credentials and host operations |

The two Samsung input paths have distinct owners: physical keyboard input goes
through MCR; Loupedeck input goes through Companion/HA. Do not bind one gesture
to both paths. Qualification must cover alternating between these controls and
the TV remote without applying stale volume state.

Do not add a general macro editor, HA adapter, replacement keyboard listener or
Logi-specific control-surface framework to MCR under this direction.

## Transitional Compatibility

The existing Apple TV helper, native remote settings and registered custom URL
interfaces still exist. Changing product direction does not make their callers
disappear. In particular, external volume URLs and Apple TV remote URLs are
different contracts; do not remove the shared URL router based on only one
family's migration.

`RemoteControlModel` resolves the Apple runtime and resumes saved pairing during
startup. Making it lazy or removing it changes cold-start behavior even if the
keyboard route is untouched. Retain that behavior until its consumers migrate.
The MCR helper and separate Companion module are distinct clients. Host shutdown
helpers that call pyatv directly are not MCR callers and retain their own
qualification. Do not assume one client's successful pairing qualifies another.

Before removing a path, combine static call-site inventory with representative
owner usage evidence. Include control-surface buttons, triggers, presets,
keybindings, custom URLs, startup registration and shutdown callers. Preserve
the current layout export, source revision and installed artifact for rollback.
Do not delete credentials or settings merely because their implementation is
scheduled for removal.

Startup registration needs runtime verification; filesystem searches alone do
not establish the state of SMAppService or all login mechanisms. The linked
inventory records the checked surfaces and remaining gaps.

Remove Apple-specific source, UI, packaging and tests coherently after caller
migration. Check shared entitlements, Bonjour declarations, termination and
URL handling before deleting them. Preserve the direct Samsung and native
keyboard regression gates, as well as the current App Store build boundary.

## Work Tracking

The [ownership decision](https://github.com/cbusillo/media-control-relay/issues/101)
and [simplification plan](https://github.com/cbusillo/media-control-relay/issues/104)
hold current inventory, acceptance evidence and sequencing. Local control-plane
qualification and artifact cleanup are tracked in
[infra/ops](https://github.com/cbusillo/shiny-infra-ops/issues/244).
