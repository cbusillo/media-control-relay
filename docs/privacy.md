# Privacy

TV Volume Bridge is designed to operate locally.

## Planned Data Handling

- Volume and mute actions are processed on the Mac and sent only to the
  configured TV on the local network.
- Input Monitoring is used only to identify supported media-key actions.
- Pairing credentials will be stored in Keychain.
- Diagnostics will redact TV addresses, credentials, session identifiers,
  device identifiers, and raw pairing responses.
- The app does not require an account, analytics service, advertising SDK, or
  cloud relay.

## Current Foundation

The current source does not monitor input, discover devices, store credentials,
or send network commands. It contains only pure routing logic and a native UI
shell that accurately reports the unconfigured state.

Any future telemetry proposal requires an explicit public design decision and
must remain opt-in.
