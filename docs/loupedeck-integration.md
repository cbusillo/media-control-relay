# Loupedeck Integration

Loupedeck support is optional and user-managed. Media Control Relay does not
bundle a Loupedeck plugin, install one automatically, mutate a Loupedeck
profile, or require Loupedeck for the App Store app to be useful. It also does
not provide dynamic feedback into the profile editor.

## Mapping Contract

Use a user-managed mapping that calls `/usr/bin/open||URL` for the exact custom
URLs below. The mapping stays local to the user's Loupedeck setup and does not
ship as a profile export in this repository.

Upper encoder:

- rotate left: `/usr/bin/open||media-control-relay://remote/volume/down`
- rotate right: `/usr/bin/open||media-control-relay://remote/volume/up`
- press: unassigned because mute is unsupported for this surface

Lower encoder:

- rotate left: `/usr/bin/open||media-control-relay://remote/seek/backward/10`
- rotate right: `/usr/bin/open||media-control-relay://remote/seek/forward/10`
- press: `/usr/bin/open||media-control-relay://remote/play-pause`

3x5 page mapping:

- row 1: back, up, home, previous, next
- row 2: left, select, right, play-pause, seek backward 30
- row 3: volume down, down, volume up, return-to-main macro, seek forward 30

The current Loupedeck desktop software can bind each action without a custom
plugin. Create the controls with **Custom > Run Command** and keep the mapping
user-managed. Do not replace `||` with a space. Do not use `.webloc` files: on
current macOS versions, Loupedeck's built-in **Desktop > Open File** action may
fail to open a custom-URL `.webloc`.

The app rejects alternate casing, percent-encoded forms, credentials, ports,
queries, fragments, unknown hosts, and extra path components. Accepted actions
use the same non-physical routing path as menu controls, do not count as
physical media-key input, and receive a small duplicate-command rate limit.

## Threat Model

The actuator is a narrow unauthenticated local interface. Any local process
that can invoke a registered custom URL may request the documented remote or
volume actions. The interface does not identify or authorize callers, and it
does not expose arbitrary remote commands. Users who need stronger isolation
should not enable a mapping for untrusted local software.

URL delivery supports cold launch without itself requesting window presentation
or activation. The setup scene ignores external events, and reopen requests are
suppressed, so repeated control actions do not present the setup window. Setup
remains available explicitly from the menu bar, and normal first-run setup
behavior remains unchanged. The app keeps only coarse aggregate diagnostics for
accepted, rejected, and rate-limited actions. It does not log raw URLs or caller
data and does not read, persist, or mutate device/private profile data.
