# Product scope

MCR retains physical Mac keyboard volume/mute, active audio/display-route
matching, direct Samsung UPnP readback and dispatch, native Mac fallback,
bounded held-key handling, permissions, recovery, and launch at login.
Companion and Home Assistant are not runtime dependencies of these features.
The optional `media-control-relay://control/volume/up`, `/down`, and `/mute`
actuators retain their existing parsing and routing behavior.

## Apple TV migration

Apple TV navigation, playback, seek and relative volume have moved to the
separate Companion module `apple-tv-pyatv`. The accepted local module version
is 0.2.3. Its physical first-press seek, Companion restart, worker recovery,
Ethernet loss/recovery and configuration rollback were qualified before this
source cleanup. See [migration evidence](https://github.com/cbusillo/media-control-relay/issues/102).

This source no longer includes the Apple TV helper, Python runtime, pairing UI,
Keychain client or remote session. All `media-control-relay://remote/...` URLs
are rejected and counted through the existing rejected-URL diagnostics; they
never fall through to active-output volume. Existing callers outside the
qualified Companion installation must migrate before adopting this build.

No saved credentials or external runtime directories are deleted on startup.
Older Apple TV preferences remain unused. The installed app is unchanged by
repository edits; signed replacement needs separate retained-function testing
and owner approval. Keep the accepted previous application as rollback until
that installation is accepted. The pre-removal source is commit
`91656bc1ecc34bf658feac9e69e844343ff81e28`; the previously qualified artifact's
source and hashes are in the historical runtime record.

## Ownership and cleanup

MCR source and distribution belong here. Companion modules own their transport
implementation; the infrastructure repository owns only local operator setup.
Do not add control-surface layouts, generic macros or HA device adapters to MCR.
Deleting redundant source does not authorize merging or replacing the installed
runtime. The removal plan is [issue 104](https://github.com/cbusillo/media-control-relay/issues/104).
