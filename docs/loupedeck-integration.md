# Loupedeck Integration

Loupedeck support is optional and user-managed. Media Control Relay does not
bundle a Loupedeck plugin, install one automatically, mutate a Loupedeck
profile, or require Loupedeck for the App Store app to be useful.

## Mapping Contract

A user-created control-surface mapping may invoke exactly these custom URLs:

- `media-control-relay://control/volume/up`
- `media-control-relay://control/volume/down`
- `media-control-relay://control/volume/mute`

The current Loupedeck desktop software can bind each action without a custom
plugin. Create three **Custom > Run Command** actions and assign them to the
desired controls. Loupedeck separates an executable from its argument with
`||`, so use these exact command values:

- `/usr/bin/open||media-control-relay://control/volume/up`
- `/usr/bin/open||media-control-relay://control/volume/down`
- `/usr/bin/open||media-control-relay://control/volume/mute`

For a single-dial mapping, create a **Custom > Dial Adjustment** named
**Active Output Volume**. Set **Left/Down** to the Volume Down command,
**Right/Up** to the Volume Up command, and assign the Mute command to the same
dial's press action. These actions follow the Mac host's active routed output;
the control name should not identify a specific TV or target device.

Do not replace `||` with a space. Do not use `.webloc` files: on current macOS
versions, Loupedeck's built-in **Desktop > Open File** action may fail to open a
custom-URL `.webloc`. Keep the mapping user-managed, and do not add device
profile exports or machine-local paths to this repository.

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

URL delivery supports cold launch without itself requesting window presentation
or activation. The setup scene ignores external events, and reopen requests are
suppressed, so repeated control actions do not present the setup window. Setup
remains available explicitly from the menu bar, and normal first-run setup
behavior remains unchanged. The app keeps only coarse aggregate diagnostics for
accepted, rejected, and rate-limited actions. It does not log raw URLs or caller
data and does not read, persist, or mutate device/private profile data.
