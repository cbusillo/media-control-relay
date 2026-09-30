# Troubleshooting

The menu-bar item and Settings show one status at a time. Find the status you
see below.

## Using Mac volume

The selected TV is not the current audio and display route, so your Mac
handles the volume keys normally. This is expected, not an error.

- Switch your Mac's sound output to the TV and make sure the TV is connected as
  a display.
- If the route should match but doesn't, open Settings and check **Selected
  Route**. Switch to the output you want, then choose the target again.

## Allow volume key access

Media Control Relay needs Input Monitoring to see the volume and mute keys.

1. In Settings, choose **Allow Volume Key Access**, or **Open Input Monitoring
   Settings**.
2. Turn on Media Control Relay in System Settings > Privacy & Security > Input
   Monitoring.
3. Choose **Quit to Apply Volume Key Access** and open the app again. macOS
   applies this permission only after the app restarts.

## Native volume display still appears

This is expected until Accessibility access is granted. Without it, volume keys
still reach the TV, and the Mac's own volume display also appears.

- To hide the native display while the TV is in control, choose **Allow Native
  HUD Replacement**, turn on Media Control Relay in System Settings > Privacy &
  Security > Accessibility, then quit and reopen the app.
- The native display always returns when the TV is not in control. The app
  keeps it whenever it cannot confirm the TV's current state.

## Allow local network access

macOS is blocking the app from reaching devices on your network.

1. Choose **Open Local Network Settings**.
2. Turn on Media Control Relay in System Settings > Privacy & Security > Local
   Network.
3. Choose **Check Local Network Access Again**.

## Can't reach your media target

The TV did not answer. The app does not report success for a key press the TV
did not confirm.

- Make sure the TV is on and on the same network as the Mac. In standby, the TV
  may not respond to network control.
- After the TV powers on from a full power loss, wait about 15 seconds for its
  network services to start, then choose **Try Reaching Target Again**.
- If the Mac switched networks, wait a moment; the app retries on its own.

## Media target rejected control

The TV refused pairing-free volume control. Check the TV's network or external
control settings, or choose another target. Media Control Relay does not pair
or store TV credentials.

## This media target isn't supported

The selected device does not offer the volume and mute control the app needs.
Choose another target and check [compatibility](compatibility.md).

## No compatible media renderers found

- Confirm the TV is on and on the same network.
- Check local network access as described above.
- Choose **Search for Media Renderers Again**.

Networks that block device discovery between clients, such as some guest or
mesh networks, can hide the TV.

## Mute does nothing

On keyboards where media keys need `Fn`, press `Fn` with Mute. In Settings,
**Last Detected** shows the most recent key the app saw.

## Launch at login

Turn on **Launch at login** in Settings. If macOS doesn't list the app under
System Settings > General > Login Items, choose **Open Login Items Settings**
and allow it there.

## Getting help

Follow [SUPPORT.md](../SUPPORT.md). Include the output of **Copy Diagnostics**.
It contains only coarse status fields and counts, never addresses, identifiers
or device names.
