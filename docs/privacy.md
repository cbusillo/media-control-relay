# Privacy

Media Control Relay is designed to operate locally.

## Data Handling

- Control actions are processed on the Mac and sent only to the selected,
  supported media target on the local network.
- Input Monitoring uses a listen-only event tap restricted to macOS
  system-defined events. Typed characters are never delivered to the app.
- During the current app run, the app keeps only aggregate event and action
  counts plus the most recently detected Volume Up, Volume Down, or Mute action
  for local setup feedback. It does not persist key histories or raw event
  payloads.
- Pairing credentials will be stored in Keychain.
- Diagnostics will redact target addresses, credentials, session identifiers,
  device identifiers, and raw pairing responses.
- The app does not require an account, analytics service, advertising SDK, or
  cloud relay.

## Current Preview

The current source can observe supported volume keys after the user grants Input
Monitoring access. It does not discover devices, store credentials, or send
network commands. Its native UI accurately reports the unconfigured target
state.

Any future telemetry proposal requires an explicit public design decision and
must remain opt-in.
