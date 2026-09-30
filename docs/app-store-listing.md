# App Store Listing Draft: 1.0.0

> [!NOTE]
> Draft for the owner's review. Nothing here has been entered in App Store
> Connect. The app record, privacy answers and export-compliance declaration
> already exist from the TestFlight qualification in
> [App Store distribution](app-store-distribution.md).

## Build

- Configuration: `AppStore` (App Sandbox, outbound and inbound network access).
- Version `1.0.0`, build `13`, the same numbers as the Developer ID release.
  App Store Connect has used builds `1` to `4` under version `0.1.0`, so `13`
  is free. If a later App Store-only rebuild is needed, raise the build number
  in `project.yml` first.
- The App Store build does not request Accessibility and does not offer native
  volume display replacement. Volume keys use the listen-only Input Monitoring
  tap. See [Accessibility in the App Store build](app-store-distribution.md#accessibility-in-the-app-store-build).

## App Information

| Field | Value |
| --- | --- |
| Name | Media Control Relay |
| Subtitle (30) | Mac volume keys for your TV |
| Primary category | Utilities |
| Secondary category | None |
| Content rights | Contains no third-party content |
| Age rating | 4+ (answer "None" or "No" to every questionnaire item) |
| Support URL | <https://github.com/cbusillo/media-control-relay/blob/main/SUPPORT.md> |
| Marketing URL | <https://github.com/cbusillo/media-control-relay> |
| Privacy policy URL | <https://github.com/cbusillo/media-control-relay/blob/main/docs/privacy.md> (already set) |
| Copyright | 2026 Shiny Computers Leasing LLC |
| Price | Owner's decision |

## Promotional Text (170)

Use your Mac keyboard's volume and mute keys on your TV. When the TV is your
sound output, the keys control the TV. Switch outputs and they control your Mac
again.

## Description

Media Control Relay lets your Mac's volume and mute keys control a compatible
TV when the TV is your Mac's current sound output and display. When you switch
to any other output, the keys go back to controlling your Mac as usual.

It lives in the menu bar and stays out of the way:

- Volume Up, Volume Down and Mute go to the selected TV over your local network.
- Volume stays with macOS whenever the TV isn't the active sound output and
  display.
- Compatible TVs are found on your network without pairing and without storing
  any credentials.
- The menu bar shows the current status, with plain recovery steps for
  permissions, network access and a TV it can't reach.
- It recovers on its own after sleep, TV standby, TV power loss and network
  changes, and never replays key presses made while the TV was unreachable.
- It can start at login.

Compatibility: tested with the Samsung UN65JU670D (2015 JU series) connected
over HDMI and used as a Mac display. Other models may work but aren't claimed.

Privacy: no account, analytics or cloud service. The app contacts only the TV
you select, on your local network.

Not included: TV power, input switching, navigation, app launching, other TV
brands and Apple TV control.

## Keywords (100)

`TV volume,volume keys,mute,HDMI,menu bar,media keys,UPnP,DLNA,television,remote,speaker`

Other companies' names stay out of keywords.

## Screenshots

Mac screenshots are required: one to ten PNG or JPEG images at 16:10, with no
transparency, at 1280×800, 1440×900, 2560×1600 or 2880×1800. Take them from
the App Store build, with no IP address, device identifier or network name
visible:

1. The menu bar popover while the TV is in control.
2. Settings, showing Volume Key Access ready and the selected TV.
3. The setup flow's Input Monitoring step.
4. The status and recovery text for a TV that can't be reached.

## App Review Information

Sign-in required: No.

Notes for the reviewer:

> Media Control Relay sends the Mac's volume and mute keys to a TV on the local
> network. It needs a compatible TV (tested with a Samsung UN65JU670D) that is
> both the Mac's current sound output over HDMI and a Mac display. Without that
> TV, the app runs, shows setup and status, and leaves the volume keys to macOS.
> A video of the app controlling the TV is attached.
>
> Input Monitoring: the app creates a listen-only event tap for system-defined
> events and reads only Volume Up, Volume Down and Mute. It never receives
> typed characters and never changes or blocks any event. It does not use
> Accessibility.
>
> Local network: the app uses SSDP discovery to find TVs, then sends UPnP
> volume and mute commands only to the TV the user selects. It uses no server,
> account or analytics.
>
> To try it without a TV: open the app from the menu bar, follow setup to grant
> Input Monitoring, then choose Find Media Renderers in Settings and allow local
> network access. Pressing the volume keys increases **Detected Presses** in
> Settings while the Mac keeps control of its own volume.

Attachment: a short screen recording, with the TV in frame, of setup, choosing
the TV, and the volume keys changing the TV's volume and mute. Only the owner
can record it, because it needs the TV.
