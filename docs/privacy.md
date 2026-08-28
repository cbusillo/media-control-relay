# Privacy

Media Control Relay is designed to operate locally.

## Data Handling

- Control actions are processed on the Mac and sent only to the selected,
  supported media target on the local network.
- Stable target identity is tracked separately from ephemeral locator data so
  diagnostics and reconciliation can avoid coupling to changing addresses.
- Input Monitoring uses a listen-only event tap restricted to macOS
  system-defined events. Typed characters are never delivered to the app.
- During the current app run, the app keeps only aggregate event and action
  counts plus the most recently detected Volume Up, Volume Down, or Mute action
  for local setup feedback. It does not persist key histories or raw event
  payloads.
- The initial pairing-free UPnP transport stores no pairing credentials. Any
  future credentialed adapter must store secrets in Keychain.
- Diagnostics will redact target addresses, credentials, session identifiers,
  device identifiers, control URLs, SSDP payloads, model strings, transport
  locators, network interface names, and raw pairing responses.
- The app does not require an account, analytics service, advertising SDK, or
  cloud relay.

## Current Preview

The current source can observe supported volume keys after the user grants Input
Monitoring access, discover compatible local media renderers, and send
pairing-free volume commands to an explicitly selected target. Discovery shows
generic ordinal labels only. The app persists the selected stable identity and
route rule, but never persists or displays the target address, control URL,
model string, SSDP payload, or SOAP payload.

Network recovery stores only a coarse path state and transition count. Interface
types may be compared in memory to detect a path change, but interface names,
addresses, gateways, endpoints, and path descriptions are never copied to
diagnostics. Empty discovery is not treated as evidence that macOS denied Local
Network access.

Confirmed presentation state contains only volume bounds, step, mute, normalized
level, coarse pending/failure/rail/lifecycle state, and local request/epoch
guards. It does not carry target identity, host data, control URLs, session
identifiers, or raw protocol responses. A muted confirmation at the target's
minimum volume may retain the last confirmed level above that minimum for
continuity, while the confirmed target volume remains unchanged and no target
state is inferred. All retained presentation state is cleared on configuration,
permission, session, sleep, and route invalidation.

Failed commands may produce one low-priority local accessibility announcement,
`Volume control unavailable`, for each command entry into the failed
presentation state. The announcement does not include target identity, failure
details, addresses, or other protocol data, and a failure cancels any deferred
volume-value announcement for that command sequence.

The transient target volume overlay renders only that in-memory presentation
state. It is excluded from the accessibility tree because the app model owns
the corresponding VoiceOver announcements; the overlay does not add another
record of values, device state, or user interaction.

Any future telemetry proposal requires an explicit public design decision and
must remain opt-in.
