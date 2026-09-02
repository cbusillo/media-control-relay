# Privacy

Media Control Relay is designed to operate locally.

## Data Handling

- Control actions are processed on the Mac and sent only to the selected,
  supported media target on the local network.
- Stable target identity is tracked separately from ephemeral locator data so
  diagnostics and reconciliation can avoid coupling to changing addresses.
- Volume-key monitoring uses a system-defined-event tap. It remains listen-only
  without Accessibility access and conditionally filters only supported volume
  gestures while a fresh selected target is ready. Typed characters are never
  delivered to the app.
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

The optional custom URL actuator is intentionally narrow and unauthenticated:
it exposes the documented local `media-control-relay://control/...` and
`media-control-relay://remote/...` URLs to local processes only. Any local
process that can invoke a registered custom URL may request those actions, so
the feature is not an authorization boundary. The app rejects noncanonical
URLs, records only coarse accepted/rejected/rate-limited counts, and never
records raw URLs, caller identity, query values, or fragments.

The actuator does not install software, discover a caller, change profiles, or
persist device/private data. Keychain remains the custody boundary for any
stored credentials, while discovered names stay ephemeral and adapter-owned. A
Loupedeck mapping is optional and user-managed; the App Store app remains
useful without Loupedeck or any bundled plugin.

## Current Preview

The current source can observe supported volume keys after the user grants Input
Monitoring access, discover compatible local media renderers, and send
pairing-free volume commands to an explicitly selected target. Discovery shows
generic ordinal labels only. The app persists the selected stable identity and
route rule, but never persists or displays the target address, control URL,
model string, SSDP payload, or SOAP payload.

The app never shows hosts, IDs, PINs, credentials, runtime paths, or other
private identifiers in UI or diagnostics. The local Apple companion helper is
the custody boundary for discovered credentials, and the user-facing names it
surfaces are ephemeral labels only.

Network recovery stores only a coarse path state and transition count. Interface
types may be compared in memory to detect a path change, but interface names,
addresses, gateways, endpoints, and path descriptions are never copied to
diagnostics. Empty discovery is not treated as evidence that macOS denied Local
Network access.

While a selected target's route remains active and conditional filtering is
available, the app performs a local target-state read every five seconds to keep
the volume-key decision fresh. The read is cancellable and generation-guarded,
retains only the same bounded confirmed volume/mute presentation state, and
stops on route, permission, lifecycle, network, session, or target failure.

Confirmed presentation state contains only volume bounds, step, mute, normalized
level, coarse pending/failure/rail/lifecycle state, and local request/epoch
guards. It does not carry target identity, host data, control URLs, session
identifiers, or raw protocol responses. A muted confirmation at the target's
minimum volume may retain the last confirmed level above that minimum for
continuity, while the confirmed target volume remains unchanged and no target
state is inferred. All retained presentation state is cleared on configuration,
permission, session, sleep, and route invalidation.

Failed commands replace the local accessible target status with `Volume control
unavailable`. The status does not include target identity, failure details,
addresses, or other protocol data. A later confirmed value replaces it, and
configuration, permission, session, sleep, and route invalidation clear it.

The transient target volume overlay renders only that in-memory presentation
state and remains excluded from the accessibility tree. The latest confirmed
target status also appears in the menu-bar item's accessibility label and menu
window until it is replaced, the relay leaves its active state, or presentation
state is invalidated. This persistent local surface is
limited to target-agnostic volume, mute, or unavailable text; it does not add a
record of target identity, addresses, protocol state, or user interaction.

## Privacy Manifest

`Config/PrivacyInfo.xcprivacy` is the machine-readable form of this policy. The
app declares no tracking domains and no collected data types. It declares only
the required-reason API categories used by app-owned code:

- `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` for the
  selected target, route rule, and permission-request state stored for this app;
  and
- `NSPrivacyAccessedAPICategorySystemBootTime` with reason `35F9.1` for relative
  gesture, route-coalescing, presentation, and SSDP scan timing based on
  `ProcessInfo.systemUptime` and `DispatchTime` uptime.

The app has no third-party package dependencies, and its linked internal
libraries are static, so the app-level manifest covers the complete shipped
code. Validation checks the exact declarations, watches for selected new
required-reason API families, and proves that the manifest is present in the
built app bundle.

The local manifest audit does not prove whether App Store Connect currently
enforces required-reason declarations for a Mac-only binary. Profile-backed
export and upload evidence remains part of issue #16. At submission time, the
App Store Connect privacy answers must remain consistent with the manifest's
no-tracking and no-collected-data declarations.

Any future telemetry proposal requires an explicit public design decision and
must remain opt-in.
