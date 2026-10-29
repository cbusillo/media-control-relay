# App Store Listing: 1.0.0

> [!NOTE]
> Listing text and App Review notes were entered in App Store Connect on
> September 30, 2026. Build 13 was uploaded and processed as `VALID`.
> The October 25 [media handoff](https://github.com/cbusillo/media-control-relay/issues/16#issuecomment-6402660680)
> and [submission record](https://github.com/cbusillo/media-control-relay/issues/16#issuecomment-6403411256)
> completed the demo, screenshot, build selection and submission. Apple
> rejected `1.0.0 (13)` on October 27 over the `network.server` entitlement.
> Build 13 was resubmitted unchanged that evening with the reviewer notes
> below; [issue #147](https://github.com/cbusillo/media-control-relay/issues/147)
> tracks the public release. Changing reviewer text requires Chris's approval
> before sending.

## Build

- Configuration: `AppStore` (App Sandbox, outbound and inbound network access).
- Version `1.0.0`, build `13`, the same numbers as the Developer ID release.
  Build `13` was uploaded under `1.0.0`; builds `1` to `4` were used under
  `0.1.0`. If a later App Store-only rebuild is needed, raise the build number
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
| Price | Free, as Chris chose on September 30, 2026 |

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

Privacy: no account, analytics or cloud service. Everything stays on your local
network: finding TVs asks the media devices there to describe themselves, and
volume and mute go only to the TV you select.

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

Stored in App Store Connect on October 27, 2026, replacing the whole earlier
Notes field. This is the exact text Chris approved on
[issue #155](https://github.com/cbusillo/media-control-relay/issues/155#issuecomment-6449034548):

> Media Control Relay requires com.apple.security.network.server to receive UDP
> replies during SSDP discovery of UPnP media renderers on the local network.
>
> The app opens a temporary UDP socket on an operating-system-assigned local
> port, sends an SSDP M-SEARCH request to 239.255.255.250:1900, and receives
> the media renderers' unicast responses on that socket. Discovery runs when
> the user chooses Find Media Renderers and when the app needs to locate the
> previously selected TV before a volume or mute operation, such as after
> launch or a network change. Each search is bounded, and the socket closes
> when the search finishes or is cancelled.
>
> The server entitlement is used only for these UDP replies. The app does not
> accept TCP connections, run a web or FTP server, or listen continuously for
> advertisements. Device-description requests and volume/mute commands use
> outgoing HTTP connections.
>
> For UDP, App Sandbox controls sending and receiving separately. In our signed
> sandboxed comparison on macOS 27.2, with Local Network access allowed for
> both probes, the client-and-server variant received parsed renderer responses
> in all six searches. The client-only variant, even without an explicit bind,
> sent its requests but could not complete discovery in any of its six
> searches. Apple's network-client entitlement documentation explains that a
> client-only UDP app can send but cannot receive data:
> <https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client>
>
> The earlier reviewer note saying the app "uses no server" did not adequately
> explain this temporary UDP reply socket. This is why the app needs the
> network.server entitlement.

Attachment: a short screen recording, with the TV in frame, of setup, choosing
the TV, and the volume keys changing the TV's volume and mute. Chris records it
hands-on, because it needs the TV.
