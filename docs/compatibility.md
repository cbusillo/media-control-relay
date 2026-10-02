# Compatibility

Media Control Relay claims compatibility only for hardware and software that
has been tested on a real device. Anything not listed here may work, but it is
not supported.

## Media Targets

| Target | Protocol | Status | Evidence |
| --- | --- | --- | --- |
| Samsung `UN65JU670D` (2015 JU series) | UPnP `RenderingControl:1`, pairing-free | Qualified for volume up, volume down and mute | [Samsung UPnP qualification](samsung-upnp-qualification.md) |
| Other Samsung models and series | — | Not claimed | — |
| Other UPnP media renderers | UPnP `RenderingControl:1` | Discoverable; not claimed | — |

The qualified setup is Mac display audio routed to the TV over HDMI, with the
TV acting as a display. Other TV inputs and source modes are not claimed.

Media Control Relay does not provide power, navigation, input selection, app
launching or pairing for any TV. Apple TV control moved to the separate
Companion module; see [product scope](product-scope.md).

## Mac

| Item | Supported |
| --- | --- |
| macOS | 15 or later. Hands-on qualification ran on macOS 27.0; macOS 15 is covered by the automated build and tests only. |
| Architecture | Tested on Apple silicon. Intel Macs are not tested. |
| Keyboard | Built-in and external keyboards that send the standard Volume Up, Volume Down and Mute media keys. On keyboards that need `Fn` for media keys, use `Fn` with the key. |
| Network | The Mac and the TV must be on the same local network. |

## Distribution

[Version 1.0.0](https://github.com/cbusillo/media-control-relay/releases/tag/v1.0.0)
is available as a Developer ID signed and notarized download. The Mac App Store
1.0.0 build has been uploaded, and earlier TestFlight builds passed installation
and permission checks. App Review acceptance is not established; see
[App Store distribution qualification](app-store-distribution.md).

## Reporting a New Model

If another TV works or fails, open an issue with the model name, the TV's
source mode, your macOS version and the output of **Copy Diagnostics** from
Settings. Diagnostics never include addresses, identifiers or model strings, so
add the model name yourself. A model is added to the table above only after it
passes the same checks as the qualified model.
