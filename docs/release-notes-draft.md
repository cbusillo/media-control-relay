# Release Notes Draft: First Public Release

> [!NOTE]
> Draft. Nothing here is published. The version number, date and download
> link are filled in when the owner approves the release.

## Media Control Relay <version>

Media Control Relay lets your Mac's volume and mute keys control a compatible
TV when the TV is your Mac's current sound output and display. When you switch
to any other output, the keys go back to controlling your Mac as usual.

### What It Does

- Sends Volume Up, Volume Down and Mute from your Mac keyboard to the selected
  TV over your local network.
- Leaves volume to macOS whenever the TV is not the active audio and display
  route.
- Finds compatible TVs on your network without pairing and without storing
  credentials.
- Shows its status in the menu bar, with plain recovery steps for permissions,
  network access and an unreachable TV.
- Recovers on its own after sleep, TV standby, TV power loss and network
  changes, without sending key presses that happened while the TV was
  unreachable.
- Optionally replaces the Mac volume display while the TV is in control, once
  you grant Accessibility access.
- Can start at login.

### Compatibility

Qualified with the Samsung `UN65JU670D` (2015 JU series) over HDMI, with the
TV as a Mac display. Other models may work but are not claimed. Requires
macOS 15 or later. See [compatibility](compatibility.md).

### Privacy

No account, analytics or cloud service. Everything stays on your local
network: finding TVs asks the media devices there to describe themselves, and
volume and mute go only to the TV you select. Diagnostics you copy contain
only coarse status fields and counts. See [privacy](privacy.md).

### Install

Download the notarized app, move it to Applications and open it. Setup asks for
volume key access (Input Monitoring) and local network access. See
[troubleshooting](troubleshooting.md) if a step doesn't work.

### Not Included

TV power, input switching, navigation, app launching, other TV brands and
Apple TV control.
