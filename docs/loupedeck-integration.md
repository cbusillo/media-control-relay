# Loupedeck Integration

Loupedeck support is optional and user-managed. Media Control Relay does not
bundle a Loupedeck plugin, install one automatically, mutate a Loupedeck
profile, or require Loupedeck for the App Store app to be useful.

## Mapping Contract

A user-created control-surface mapping may invoke exactly these custom URLs:

- `media-control-relay://control/volume/up`
- `media-control-relay://control/volume/down`
- `media-control-relay://control/volume/mute`

The app rejects alternate casing, percent-encoded forms, credentials, ports,
queries, fragments, unknown hosts, and extra path components. Accepted actions
use the same non-physical routing path as menu controls, do not count as
physical media-key input, and receive a small duplicate-command rate limit.

## Threat Model

The actuator is a narrow unauthenticated local interface. Any local process
that can invoke a registered custom URL may request Volume Up, Volume Down, or
Mute. The interface does not identify or authorize callers, and it does not
expose arbitrary remote commands. Users who need stronger isolation should not
enable a mapping for untrusted local software.

URL delivery supports cold launch without opening or activating a window. The
app keeps only bounded aggregate diagnostics for accepted, rejected, and
rate-limited actions. It does not log raw URLs or caller data and does not read,
persist, or mutate device/private profile data.
